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

# Global variables to track model status
MODEL_PATH = 'model/best.pt'
TRAINING_IN_PROGRESS = False
TRAINING_PROGRESS = 0.0
MODEL_AVAILABLE = os.path.exists(MODEL_PATH)
LOCK = threading.Lock()

# Create directories for storing data
os.makedirs('model', exist_ok=True)
os.makedirs('datasets/train/images', exist_ok=True)
os.makedirs('datasets/train/labels', exist_ok=True)
os.makedirs('datasets/val/images', exist_ok=True)
os.makedirs('datasets/val/labels', exist_ok=True)

class YOLOModel:
    @staticmethod
    def get_model_status():
        """Return the current model status"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE
        with LOCK:
            return {
                'training_in_progress': TRAINING_IN_PROGRESS,
                'progress': TRAINING_PROGRESS,
                'model_available': MODEL_AVAILABLE
            }
    
    @staticmethod
    def prepare_data(images_data):
        """Prepare dataset for YOLO training"""
        # Clear previous dataset
        shutil.rmtree('datasets/train/images', ignore_errors=True)
        shutil.rmtree('datasets/train/labels', ignore_errors=True)
        shutil.rmtree('datasets/val/images', ignore_errors=True)
        shutil.rmtree('datasets/val/labels', ignore_errors=True)
        
        os.makedirs('datasets/train/images', exist_ok=True)
        os.makedirs('datasets/train/labels', exist_ok=True)
        os.makedirs('datasets/val/images', exist_ok=True)
        os.makedirs('datasets/val/labels', exist_ok=True)
        
        # Create class mapping for the labels
        classes = set()
        for img in images_data:
            for box in img.get('boundingBoxes', []):
                # Only include verified boxes
                if box.get('isVerified', False):
                    classes.add(box.get('label'))
        
        class_names = sorted(list(classes))
        class_map = {name: idx for idx, name in enumerate(class_names)}
        
        # Save class mapping
        with open('model/classes.json', 'w') as f:
            json.dump(class_map, f)
        
        # Split data: 80% training, 20% validation
        np.random.seed(42)
        train_indices = np.random.choice(
            len(images_data), 
            int(0.8 * len(images_data)), 
            replace=False
        )
        train_set = set(train_indices)
        
        for i, img_data in enumerate(images_data):
            # Only process images with verified boxes
            verified_boxes = [box for box in img_data.get('boundingBoxes', []) 
                             if box.get('isVerified', False)]
            
            if not verified_boxes:
                continue
                
            filename = img_data.get('filepath')
            if not filename:
                continue
                
            # Source and destination paths
            src_path = os.path.join('uploads', filename)
            
            if not os.path.exists(src_path):
                continue
                
            # Determine if this is for train or validation
            if i in train_set:
                img_dest = os.path.join('datasets/train/images', filename)
                label_dest = os.path.join('datasets/train/labels', os.path.splitext(filename)[0] + '.txt')
            else:
                img_dest = os.path.join('datasets/val/images', filename)
                label_dest = os.path.join('datasets/val/labels', os.path.splitext(filename)[0] + '.txt')
            
            # Copy image file
            shutil.copy2(src_path, img_dest)
            
            # Convert annotations to YOLO format and save
            with open(label_dest, 'w') as f:
                for box in verified_boxes:
                    # YOLO format: class_id center_x center_y width height
                    # All values are normalized [0-1]
                    class_id = class_map.get(box.get('label', ''), 0)
                    x = box.get('x', 0.0)
                    y = box.get('y', 0.0)
                    w = box.get('width', 0.0)
                    h = box.get('height', 0.0)
                    
                    # Convert to center coordinates
                    center_x = x + w/2
                    center_y = y + h/2
                    
                    f.write(f"{class_id} {center_x} {center_y} {w} {h}\n")
        
        # Create dataset.yaml for YOLO
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
        
        return len(train_set) > 0

    @staticmethod
    def train_model_thread(images_data):
        """Train YOLO model in a separate thread"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE
        
        try:
            with LOCK:
                TRAINING_IN_PROGRESS = True
                TRAINING_PROGRESS = 0.0
            
            # Prepare the data
            data_ready = YOLOModel.prepare_data(images_data)
            if not data_ready:
                with LOCK:
                    TRAINING_IN_PROGRESS = False
                return
            
            # Create or load model
            if os.path.exists(MODEL_PATH):
                model = YOLO(MODEL_PATH)
            else:
                model = YOLO('yolov8n.pt')  # Use YOLOv8 nano as base model
            
            # Define a custom callback function to update progress
            def on_train_epoch_end(trainer):
                global TRAINING_PROGRESS
                total_epochs = trainer.epochs
                current_epoch = trainer.epoch + 1  # +1 because epochs are 0-indexed
                progress = current_epoch / total_epochs
                with LOCK:
                    TRAINING_PROGRESS = progress
                print(f"Training progress: {progress:.2f} - Epoch {current_epoch}/{total_epochs}")
            
            # Register the callback with the YOLO model
            model.add_callback("on_train_epoch_end", on_train_epoch_end)
            
            # Train the model
            model.train(
                data='datasets/dataset.yaml',
                epochs=50,
                imgsz=640,
                batch=16,
                patience=0,  # Set to 0 to disable early stopping
                project='model',
                name='training',
                exist_ok=True
            )
            
            # Copy the best model
            best_model = os.path.join('model', 'training', 'weights', 'best.pt')
            if os.path.exists(best_model):
                shutil.copy2(best_model, MODEL_PATH)
            
            with LOCK:
                TRAINING_IN_PROGRESS = False
                MODEL_AVAILABLE = os.path.exists(MODEL_PATH)
                TRAINING_PROGRESS = 1.0
                
        except Exception as e:
            print(f"Error training model: {e}")
            with LOCK:
                TRAINING_IN_PROGRESS = False
    
    @staticmethod
    def start_training(images_data):
        """Start model training in a separate thread"""
        global TRAINING_IN_PROGRESS
        
        with LOCK:
            if TRAINING_IN_PROGRESS:
                return False
        
        # Start training in a separate thread
        threading.Thread(
            target=YOLOModel.train_model_thread,
            args=(images_data,),
            daemon=True
        ).start()
        
        return True
    
    @staticmethod
    def predict(filename):
        """Make predictions for an image"""
        global MODEL_AVAILABLE
        
        if not MODEL_AVAILABLE:
            return []
            
        # Load class mapping
        try:
            with open('model/classes.json', 'r') as f:
                class_map = json.load(f)
        except:
            return []
            
        # Reverse the class map
        class_names = {idx: name for name, idx in class_map.items()}
        
        # Load the model
        model = YOLO(MODEL_PATH)
        
        # Run inference
        img_path = os.path.join('uploads', filename)
        if not os.path.exists(img_path):
            return []
            
        results = model(img_path)
        
        # Process the results
        predictions = []
        for result in results:
            boxes = result.boxes
            for i, box in enumerate(boxes):
                x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                
                # Get image dimensions
                img = Image.open(img_path)
                img_width, img_height = img.size
                
                # Convert to normalized coordinates
                x = x1 / img_width
                y = y1 / img_height
                width = (x2 - x1) / img_width
                height = (y2 - y1) / img_height
                
                # Get class and confidence
                cls = int(box.cls.item())
                conf = float(box.conf.item())
                
                label = class_names.get(cls, f"unknown_{cls}")
                
                predictions.append({
                    'x': x,
                    'y': y,
                    'width': width,
                    'height': height,
                    'label': label,
                    'confidence': conf
                })
        
        return predictions