import os
import shutil
import json
import threading
import time
import numpy as np
from PIL import Image
import torch
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from ultralytics import YOLO
from image_augmenter import ImageAugmenter
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables to track model status
MODEL_PATH = 'model/last.pt'
TRAINING_IN_PROGRESS = False
TRAINING_PROGRESS = 0.0
MODEL_AVAILABLE = os.path.exists(MODEL_PATH) or os.path.exists('model/training/weights/last.pt')
MODEL_READY = MODEL_AVAILABLE  # Model is ready if it's available
LOCK = threading.Lock()

# Create directories for storing data
os.makedirs('model', exist_ok=True)
os.makedirs('datasets/train/images', exist_ok=True)
os.makedirs('datasets/train/labels', exist_ok=True)
os.makedirs('datasets/val/images', exist_ok=True)
os.makedirs('datasets/val/labels', exist_ok=True)

# Initialize the model flags at startup
if os.path.exists(MODEL_PATH) or os.path.exists('model/training/weights/last.pt'):
    MODEL_AVAILABLE = True
    MODEL_READY = True
    logger.info("YOLO model found at startup, setting as ready for predictions")

class YOLOModel:
    # Add class variables for model caching
    _cached_model = None
    _cached_model_path = None
    _cached_class_map = None
    
    @staticmethod
    def get_model_status():
        """Return the current model status"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE, MODEL_READY
        with LOCK:
            # Check both possible model locations
            model_available = os.path.exists(MODEL_PATH) or os.path.exists('model/training/weights/last.pt')
            return {
                'training_in_progress': TRAINING_IN_PROGRESS,
                'progress': TRAINING_PROGRESS,
                'is_available': model_available,
                'is_ready': MODEL_READY
            }
    
    @staticmethod
    def prepare_data(images_data):
        """Prepare dataset for YOLO training"""
        logger.info("Starting data preparation")
        logger.info(f"Received {len(images_data)} images for preparation")
        
        # First, ensure class consistency across all components
        try:
            logger.info("Ensuring class mapping consistency")
            import sys
            import os
            sys.path.append(os.path.dirname(os.path.abspath(__file__)))
            from ensure_class_consistency import main as ensure_consistency
            ensure_consistency()
            logger.info("Class mapping consistency check completed")
        except Exception as e:
            logger.error(f"Error ensuring class consistency: {str(e)}")
            # Continue anyway, as we'll create a new class mapping below
        
        # Verify that all images are fully annotated
        for img in images_data:
            filename = img.get('filename', 'unknown')
            fully_annotated = img.get('isFullyAnnotated', False)
            if not fully_annotated:
                logger.warning(f"Image {filename} is not marked as fully annotated - skipping")
                continue
                
            # Count verified annotations
            verified_boxes = [box for box in img.get('annotations', []) if box.get('isVerified', False)]
            logger.info(f"Image {filename} has {len(verified_boxes)} verified annotations")
        
        # Filter out images without any verified annotations
        valid_images = []
        for img in images_data:
            verified_boxes = [box for box in img.get('annotations', []) if box.get('isVerified', False)]
            if verified_boxes:
                valid_images.append(img)
            else:
                logger.warning(f"Image {img.get('filename', 'unknown')} has no verified annotations - skipping")
        
        logger.info(f"After filtering, {len(valid_images)} images have verified annotations")
        
        if not valid_images:
            logger.error("No images with verified annotations found")
            return False
        
        # Clear previous dataset but preserve augmented images
        logger.info("Clearing previous dataset")
        for dir_path in ['datasets/train/images', 'datasets/train/labels', 'datasets/val/images', 'datasets/val/labels']:
            if os.path.exists(dir_path):
                for filename in os.listdir(dir_path):
                    # Skip augmented images
                    if '_aug' in filename:
                        continue
                    file_path = os.path.join(dir_path, filename)
                    try:
                        if os.path.isfile(file_path):
                            os.remove(file_path)
                    except Exception as e:
                        logger.error(f"Error removing file {file_path}: {str(e)}")
        
        # Ensure directories exist
        os.makedirs('datasets/train/images', exist_ok=True)
        os.makedirs('datasets/train/labels', exist_ok=True)
        os.makedirs('datasets/val/images', exist_ok=True)
        os.makedirs('datasets/val/labels', exist_ok=True)
        
        # Create class mapping for the labels
        logger.info("Creating class mapping")
        classes = set()
        for img in valid_images:
            logger.info(f"Processing image {img.get('filename')} for class mapping")
            for box in img.get('annotations', []):
                if box.get('isVerified', False):
                    label = box.get('label', '')
                    logger.info(f"Found verified label: {label}")
                    classes.add(label)
        
        class_names = sorted(list(classes))
        class_map = {name: idx for idx, name in enumerate(class_names)}
        logger.info(f"Found {len(class_map)} classes: {class_names}")
        logger.info(f"Class mapping: {class_map}")
        
        if not class_map:
            logger.error("No classes found in verified annotations")
            return False
        
        # Save class mapping
        with open('model/classes.json', 'w') as f:
            json.dump(class_map, f)
        logger.info("Saved class mapping to model/classes.json")
        
        # Split data: 80% training, 20% validation
        logger.info("Splitting data into training and validation sets")
        np.random.seed(42)
        train_indices = np.random.choice(
            len(valid_images), 
            int(0.8 * len(valid_images)), 
            replace=False
        )
        train_set = set(train_indices)
        logger.info(f"Split: {len(train_set)} training images, {len(valid_images) - len(train_set)} validation images")
        
        successful_train_images = 0
        successful_val_images = 0
        
        # Process in batches to be more memory efficient
        logger.info("Processing images in batches")
        batch_size = 5
        
        def validate_and_convert_box(box, img_width, img_height):
            """Validate and convert box coordinates to YOLO format"""
            try:
                x = float(box.get('x', 0.0))
                y = float(box.get('y', 0.0))
                w = float(box.get('width', 0.0))
                h = float(box.get('height', 0.0))
                
                # Ensure coordinates are within [0, 1]
                x = max(0.0, min(1.0, x))
                y = max(0.0, min(1.0, y))
                w = max(0.0, min(1.0, w))
                h = max(0.0, min(1.0, h))
                
                # Convert to center coordinates
                center_x = x + w/2
                center_y = y + h/2
                
                # Ensure center coordinates are within [0, 1]
                center_x = max(0.0, min(1.0, center_x))
                center_y = max(0.0, min(1.0, center_y))
                
                # Ensure width and height don't exceed image bounds
                w = min(w, 1.0 - x)
                h = min(h, 1.0 - y)
                
                return center_x, center_y, w, h
            except Exception as e:
                logger.error(f"Error validating box coordinates: {str(e)}")
                return None
        
        for batch_start in range(0, len(valid_images), batch_size):
            batch_end = min(batch_start + batch_size, len(valid_images))
            logger.info(f"Processing batch {batch_start // batch_size + 1}, images {batch_start}-{batch_end-1}")
            
            for i in range(batch_start, batch_end):
                img_data = valid_images[i]
                
                # Only process images with verified boxes
                verified_boxes = [box for box in img_data.get('annotations', []) 
                                if box.get('isVerified', False)]
                
                if not verified_boxes:
                    logger.warning(f"No verified boxes in image {i}, skipping")
                    continue
                    
                filename = img_data.get('filename')
                if not filename:
                    logger.warning(f"No filename for image {i}, skipping")
                    continue
                    
                # Source and destination paths
                src_path = os.path.join('uploads', filename)
                
                if not os.path.exists(src_path):
                    logger.warning(f"Source image not found: {src_path}, skipping")
                    continue
                
                # Get image dimensions
                try:
                    with Image.open(src_path) as img:
                        img_width, img_height = img.size
                except Exception as e:
                    logger.error(f"Error getting image dimensions for {filename}: {str(e)}")
                    continue
                    
                # Determine if this is for train or validation
                if i in train_set:
                    logger.info(f"Processing training image: {filename}")
                    img_dest = os.path.join('datasets/train/images', filename)
                    label_dest = os.path.join('datasets/train/labels', os.path.splitext(filename)[0] + '.txt')
                    
                    try:
                        shutil.copy2(src_path, img_dest)
                        
                        with open(label_dest, 'w') as f:
                            for box in verified_boxes:
                                # Get numeric class ID from the mapping
                                class_id = class_map.get(box.get('label', ''))
                                if class_id is None:
                                    logger.warning(f"Unknown class label: {box.get('label')}, skipping")
                                    continue
                                
                                # Validate and convert box coordinates
                                coords = validate_and_convert_box(box, img_width, img_height)
                                if coords is None:
                                    continue
                                
                                center_x, center_y, w, h = coords
                                
                                # Write YOLO format: class_id center_x center_y width height
                                f.write(f"{class_id} {center_x} {center_y} {w} {h}\n")
                        
                        successful_train_images += 1
                        logger.info(f"Successfully processed training image: {filename}")
                    except Exception as e:
                        logger.error(f"Error processing training image {filename}: {str(e)}", exc_info=True)
                else:
                    logger.info(f"Processing validation image: {filename}")
                    img_dest = os.path.join('datasets/val/images', filename)
                    label_dest = os.path.join('datasets/val/labels', os.path.splitext(filename)[0] + '.txt')
                    
                    try:
                        shutil.copy2(src_path, img_dest)
                        
                        with open(label_dest, 'w') as f:
                            for box in verified_boxes:
                                # Get numeric class ID from the mapping
                                class_id = class_map.get(box.get('label', ''))
                                if class_id is None:
                                    logger.warning(f"Unknown class label: {box.get('label')}, skipping")
                                    continue
                                
                                # Validate and convert box coordinates
                                coords = validate_and_convert_box(box, img_width, img_height)
                                if coords is None:
                                    continue
                                
                                center_x, center_y, w, h = coords
                                
                                # Write YOLO format: class_id center_x center_y width height
                                f.write(f"{class_id} {center_x} {center_y} {w} {h}\n")
                        
                        successful_val_images += 1
                        logger.info(f"Successfully processed validation image: {filename}")
                    except Exception as e:
                        logger.error(f"Error processing validation image {filename}: {str(e)}", exc_info=True)
            
            # Force garbage collection after each batch
            import gc
            gc.collect()

        # Create dataset.yaml for YOLO
        logger.info("Creating dataset configuration")
        dataset_config = {
            'path': os.path.abspath('datasets'),
            'train': 'train/images',
            'val': 'val/images',
            'nc': len(class_map),
            'names': class_names
        }
        
        with open('datasets/dataset.yaml', 'w') as f:
            for key, value in dataset_config.items():
                if key == 'names':
                    f.write(f"{key}: {value}\n")
                else:
                    f.write(f"{key}: {value}\n")
        
        logger.info(f"Data preparation completed. Successfully processed {successful_train_images} training images and {successful_val_images} validation images")
        return successful_train_images > 0 and successful_val_images > 0

    @staticmethod
    def train_model_thread(images_data):
        """Train YOLO model in a separate thread"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE, MODEL_READY
        
        try:
            logger.info("Starting model training thread")
            with LOCK:
                TRAINING_IN_PROGRESS = True
                TRAINING_PROGRESS = 0.0
                MODEL_READY = False
            
            # Prepare the data
            logger.info("Preparing training data")
            data_ready = YOLOModel.prepare_data(images_data)
            if not data_ready:
                logger.error("Data preparation failed")
                with LOCK:
                    TRAINING_IN_PROGRESS = False
                return
            
            # Create or load model
            logger.info("Loading YOLO model")
            if os.path.exists(MODEL_PATH):
                model = YOLO(MODEL_PATH)
                logger.info("Loaded existing model")
            else:
                model = YOLO('yolov8n.pt')  # Use YOLOv8 nano as base model
                logger.info("Created new model from base")
            
            # Define a custom callback function to update progress
            def on_train_epoch_end(trainer):
                global TRAINING_PROGRESS
                total_epochs = trainer.epochs
                current_epoch = trainer.epoch + 1  # +1 because epochs are 0-indexed
                progress = current_epoch / total_epochs
                with LOCK:
                    TRAINING_PROGRESS = progress
                logger.info(f"Training progress: {progress:.2f} - Epoch {current_epoch}/{total_epochs}")
            
            # Register the callback with the YOLO model
            model.add_callback("on_train_epoch_end", on_train_epoch_end)
            
            # Use a memory-efficient approach for training
            logger.info("Starting model training with memory-efficient settings")
            model.train(
                data='datasets/dataset.yaml',
                epochs=20,
                imgsz=640,
                batch=32,
                patience=5,
                project='model',
                name='training',
                exist_ok=True,
                verbose=True,
                workers=0,
            )
            
            # Copy the best model
            logger.info("Training completed, copying best model")
            best_model = os.path.join('model', 'training', 'weights', 'best.pt')
            if os.path.exists(best_model):
                shutil.copy2(best_model, MODEL_PATH)
                logger.info("Best model copied successfully")
            else:
                logger.warning("Best model not found")
            
            with LOCK:
                TRAINING_IN_PROGRESS = False
                MODEL_AVAILABLE = os.path.exists(MODEL_PATH) or os.path.exists(best_model)
                TRAINING_PROGRESS = 1.0
            
            # Set model as ready for predictions
            with LOCK:
                MODEL_READY = True
                logger.info("Model is now ready for predictions")
                
        except Exception as e:
            logger.error(f"Error training model: {str(e)}", exc_info=True)
            with LOCK:
                TRAINING_IN_PROGRESS = False
    
    @staticmethod
    def start_training(images_data):
        """Start model training in a separate thread"""
        global TRAINING_IN_PROGRESS, MODEL_READY
        
        with LOCK:
            if TRAINING_IN_PROGRESS:
                return False
            
            # Explicitly set model as NOT ready at the beginning of training
            MODEL_READY = False
            TRAINING_IN_PROGRESS = True
        
        # Start training in a separate thread
        threading.Thread(
            target=YOLOModel.train_model_thread,
            args=(images_data,),
            daemon=True
        ).start()
        
        return True
    
    @staticmethod
    def _load_model_if_needed(use_latest=True):
        """Load and cache the model if not already loaded or if path changed"""
        global TRAINING_IN_PROGRESS, MODEL_READY
        
        with LOCK:
            if TRAINING_IN_PROGRESS or not MODEL_READY:
                return None, None
        
        # Create a list of potential model paths to try
        model_paths = []
        
        if use_latest:
            model_paths.extend([
                'model/training/weights/best.pt',
                'model/best.pt',
                'model/training/weights/last.pt',
                'model/last.pt',
                'yolov8n.pt'
            ])
        else:
            model_paths.extend([
                'model/best.pt',
                'model/last.pt',
                'model/training/weights/best.pt',
                'model/training/weights/last.pt',
                'yolov8n.pt'
            ])
        
        # Find the first available model path
        current_model_path = None
        for path in model_paths:
            if os.path.exists(path):
                file_size = os.path.getsize(path)
                if file_size >= 10000:  # At least 10KB
                    current_model_path = path
                    break
        
        if current_model_path is None:
            logger.error("No valid model weights found")
            return None, None
        
        # Check if we need to reload the model
        if (YOLOModel._cached_model is None or 
            YOLOModel._cached_model_path != current_model_path):
            
            try:
                logger.info(f"Loading/reloading model from {current_model_path}")
                YOLOModel._cached_model = YOLO(current_model_path)
                YOLOModel._cached_model_path = current_model_path
                logger.info(f"Successfully cached model from {current_model_path}")
            except Exception as e:
                logger.error(f"Failed to load model from {current_model_path}: {str(e)}")
                YOLOModel._cached_model = None
                YOLOModel._cached_model_path = None
                return None, None
        
        # Load class mapping if not cached
        if YOLOModel._cached_class_map is None:
            try:
                with open('model/classes.json', 'r') as f:
                    class_map = json.load(f)
                YOLOModel._cached_class_map = {idx: name for name, idx in class_map.items()}
                logger.info(f"Cached class mapping with {len(YOLOModel._cached_class_map)} classes")
            except Exception as e:
                logger.error(f"Error loading class mapping: {str(e)}")
                return None, None
        
        return YOLOModel._cached_model, YOLOModel._cached_class_map

    @staticmethod
    def predict_batch(filenames, use_latest=True):
        """Get predictions for multiple images in batch"""
        try:
            logger.info(f"Making batch predictions for {len(filenames)} images")
            
            # Load model and class mapping
            model, class_names = YOLOModel._load_model_if_needed(use_latest)
            if model is None or class_names is None:
                logger.warning("Model or class mapping not available for batch prediction")
                return {filename: [] for filename in filenames}
            
            # Prepare image paths and validate they exist
            valid_images = []
            valid_filenames = []
            
            for filename in filenames:
                img_path = f'uploads/{filename}'
                if os.path.exists(img_path):
                    valid_images.append(img_path)
                    valid_filenames.append(filename)
                else:
                    logger.warning(f"Image file not found: {img_path}")
            
            if not valid_images:
                logger.warning("No valid images found for batch prediction")
                return {filename: [] for filename in filenames}
            
            # Run batch inference
            logger.info(f"Running batch inference on {len(valid_images)} images")
            results = model(valid_images)
            
            # Process results for each image
            batch_predictions = {}
            
            for i, (filename, result) in enumerate(zip(valid_filenames, results)):
                predictions = []
                boxes = result.boxes
                
                if boxes is not None:
                    # Load image for dimensions
                    img_path = f'uploads/{filename}'
                    img = Image.open(img_path)
                    width, height = img.size
                    
                    for box in boxes:
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        conf = float(box.conf[0])
                        cls = int(box.cls[0])
                        
                        # Get class name from mapping
                        label = class_names.get(cls, f"unknown_{cls}")
                        
                        # Convert coordinates to normalized format
                        x = x1 / width
                        y = y1 / height
                        w = (x2 - x1) / width
                        h = (y2 - y1) / height
                        
                        # Ensure coordinates are within [0,1] range
                        x = max(0.0, min(0.999, x))
                        y = max(0.0, min(0.999, y))
                        w = max(0.001, min(1.0 - x, w))
                        h = max(0.001, min(1.0 - y, h))
                        
                        predictions.append({
                            'x': x,
                            'y': y,
                            'width': w,
                            'height': h,
                            'label': label,
                            'confidence': conf,
                            'source': 'ai',
                            'isVerified': False
                        })
                
                batch_predictions[filename] = predictions
                logger.info(f"Generated {len(predictions)} predictions for {filename}")
            
            # Add empty results for files that weren't processed
            for filename in filenames:
                if filename not in batch_predictions:
                    batch_predictions[filename] = []
            
            logger.info(f"Batch prediction completed for {len(filenames)} images")
            return batch_predictions
            
        except Exception as e:
            logger.error(f"Error in batch prediction: {str(e)}", exc_info=True)
            return {filename: [] for filename in filenames}

    @staticmethod
    def predict(filename, use_latest=True):
        """Get predictions for a single image (backwards compatibility)"""
        try:
            logger.info(f"Making single prediction for {filename}")
            
            # Use batch prediction with single image
            batch_results = YOLOModel.predict_batch([filename], use_latest)
            return batch_results.get(filename, [])
            
        except Exception as e:
            logger.error(f"Error getting predictions: {str(e)}", exc_info=True)
            return []

    @staticmethod
    def reset():
        global MODEL_AVAILABLE, MODEL_READY
        with LOCK:
            MODEL_AVAILABLE = False
            MODEL_READY = False
        # Clear cached model
        YOLOModel._cached_model = None
        YOLOModel._cached_model_path = None
        YOLOModel._cached_class_map = None
        logger.info("Reset YOLO model and cleared cache")