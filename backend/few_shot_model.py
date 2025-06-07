import os
import shutil
import json
import threading
import time
import numpy as np
import random
from PIL import Image
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import torchvision.transforms as transforms
from torchvision.models import resnet50, ResNet50_Weights
import logging
import random

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables to track model status
MODEL_PATH = 'model/few_shot_model.pt'
TRAINING_IN_PROGRESS = False
TRAINING_PROGRESS = 0.0
MODEL_AVAILABLE = os.path.exists(MODEL_PATH)
MODEL_READY = MODEL_AVAILABLE  # Model is ready if it's available
LOCK = threading.Lock()

class FewShotDataset(Dataset):
    def __init__(self, images_data, transform=None):
        self.images_data = images_data
        self.transform = transform or transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        
        # Create class mapping
        self.classes = set()
        for img in images_data:
            for box in img.get('annotations', []):
                if box.get('isVerified', False):
                    self.classes.add(box.get('label'))
        
        self.class_names = sorted(list(self.classes))
        self.class_map = {name: idx for idx, name in enumerate(self.class_names)}
        
        # Save class mapping
        with open('model/few_shot_classes.json', 'w') as f:
            json.dump(self.class_map, f)
    
    def __len__(self):
        return len(self.images_data)
    
    def __getitem__(self, idx):
        img_data = self.images_data[idx]
        filename = img_data.get('filename')
        img_path = os.path.join('uploads', filename)
        
        # Load image
        image = Image.open(img_path).convert('RGB')
        
        # Get verified boxes
        verified_boxes = [box for box in img_data.get('annotations', []) 
                         if box.get('isVerified', False)]
        
        # Create target tensor
        target = torch.zeros(len(self.class_names))
        for box in verified_boxes:
            class_idx = self.class_map[box.get('label')]
            target[class_idx] = 1.0
        
        if self.transform:
            image = self.transform(image)
        
        return image, target

class FewShotModel(nn.Module):
    def __init__(self, num_classes):
        super(FewShotModel, self).__init__()
        # Load pre-trained ResNet50
        self.backbone = resnet50(weights=ResNet50_Weights.DEFAULT)
        # Replace the final layer
        in_features = self.backbone.fc.in_features
        self.backbone.fc = nn.Sequential(
            nn.Linear(in_features, 512),
            nn.ReLU(),
            nn.Dropout(0.5),
            nn.Linear(512, num_classes),
            nn.Sigmoid()
        )
    
    def forward(self, x):
        return self.backbone(x)

class FewShotModelTrainer:
    # Add class variables for model caching
    _cached_model = None
    _cached_class_names = None
    _cached_transform = None
    _cached_device = None

    @staticmethod
    def get_model_status():
        """Return the current model status"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE, MODEL_READY
        with LOCK:
            return {
                'training_in_progress': TRAINING_IN_PROGRESS,
                'progress': TRAINING_PROGRESS,
                'is_available': MODEL_AVAILABLE,
                'is_ready': MODEL_READY
            }
    
    @staticmethod
    def prepare_data(images_data):
        """Prepare dataset for few-shot learning"""
        logger.info("Starting data preparation")
        
        # Create dataset
        dataset = FewShotDataset(images_data)
        logger.info(f"Created dataset with {len(dataset)} images and {len(dataset.class_names)} classes")
        
        return dataset
    
    @staticmethod
    def train_model_thread(images_data):
        """Train few-shot model in a separate thread"""
        global TRAINING_IN_PROGRESS, TRAINING_PROGRESS, MODEL_AVAILABLE, MODEL_READY
        
        try:
            logger.info("Starting model training thread")
            with LOCK:
                TRAINING_IN_PROGRESS = True
                TRAINING_PROGRESS = 0.0
                MODEL_READY = False
            
            # Prepare the data
            logger.info("Preparing training data")
            dataset = FewShotModelTrainer.prepare_data(images_data)
            
            # Create data loader
            train_loader = DataLoader(dataset, batch_size=32, shuffle=True)
            
            # Initialize model
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            model = FewShotModel(len(dataset.class_names)).to(device)
            
            # Define loss function and optimizer
            criterion = nn.BCELoss()
            optimizer = optim.Adam(model.parameters(), lr=0.001)
            
            # Early stopping parameters
            best_loss = float('inf')
            patience = 5
            patience_counter = 0
            
            # Training loop
            num_epochs = 20
            for epoch in range(num_epochs):
                model.train()
                total_loss = 0
                
                for batch_idx, (data, target) in enumerate(train_loader):
                    data, target = data.to(device), target.to(device)
                    
                    optimizer.zero_grad()
                    output = model(data)
                    loss = criterion(output, target)
                    loss.backward()
                    optimizer.step()
                    
                    total_loss += loss.item()
                
                avg_loss = total_loss / len(train_loader)
                
                # Update progress
                progress = (epoch + 1) / num_epochs
                with LOCK:
                    TRAINING_PROGRESS = progress
                logger.info(f"Epoch {epoch+1}/{num_epochs}, Loss: {avg_loss:.4f}")
                
                # Early stopping check
                if avg_loss < best_loss:
                    best_loss = avg_loss
                    patience_counter = 0
                    # Save best model
                    torch.save({
                        'model_state_dict': model.state_dict(),
                        'class_names': dataset.class_names
                    }, MODEL_PATH)
                    logger.info(f"New best loss: {best_loss:.4f}, model saved")
                else:
                    patience_counter += 1
                    logger.info(f"No improvement. Patience: {patience_counter}/{patience}")
                    
                    if patience_counter >= patience:
                        logger.info(f"Early stopping triggered after {epoch+1} epochs")
                        break
            
            # Ensure model is saved (in case early stopping didn't trigger)
            if not os.path.exists(MODEL_PATH):
                torch.save({
                    'model_state_dict': model.state_dict(),
                    'class_names': dataset.class_names
                }, MODEL_PATH)
            
            with LOCK:
                TRAINING_IN_PROGRESS = False
                MODEL_AVAILABLE = True
                TRAINING_PROGRESS = 1.0
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
            target=FewShotModelTrainer.train_model_thread,
            args=(images_data,),
            daemon=True
        ).start()
        
        return True
    
    @staticmethod
    def _load_model_if_needed():
        """Load and cache the model if not already loaded"""
        global MODEL_AVAILABLE, TRAINING_IN_PROGRESS, MODEL_READY
        
        with LOCK:
            if TRAINING_IN_PROGRESS or not MODEL_READY or not MODEL_AVAILABLE:
                return None, None, None, None
        
        # Check if model is already cached
        if (FewShotModelTrainer._cached_model is not None and 
            FewShotModelTrainer._cached_class_names is not None):
            return (FewShotModelTrainer._cached_model, 
                   FewShotModelTrainer._cached_class_names,
                   FewShotModelTrainer._cached_transform,
                   FewShotModelTrainer._cached_device)
        
        try:
            # Load model and class mapping
            checkpoint = torch.load(MODEL_PATH)
            class_names = checkpoint['class_names']
            
            # Initialize model
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            model = FewShotModel(len(class_names)).to(device)
            model.load_state_dict(checkpoint['model_state_dict'])
            model.eval()
            
            # Create transform
            transform = transforms.Compose([
                transforms.Resize((224, 224)),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
            ])
            
            # Cache everything
            FewShotModelTrainer._cached_model = model
            FewShotModelTrainer._cached_class_names = class_names
            FewShotModelTrainer._cached_transform = transform
            FewShotModelTrainer._cached_device = device
            
            logger.info(f"Successfully cached FewShot model with {len(class_names)} classes")
            return model, class_names, transform, device
            
        except Exception as e:
            logger.error(f"Error loading FewShot model: {str(e)}", exc_info=True)
            return None, None, None, None

    @staticmethod
    def predict_batch(filenames):
        """Make predictions for multiple images"""
        try:
            logger.info(f"Making batch predictions for {len(filenames)} FewShot images")
            
            # Load model components
            model, class_names, transform, device = FewShotModelTrainer._load_model_if_needed()
            if model is None:
                logger.warning("FewShot model not available for batch prediction")
                return {filename: [] for filename in filenames}
            
            batch_predictions = {}
            
            # Process images in batches for memory efficiency
            batch_size = 16  # Adjust based on GPU memory
            
            for i in range(0, len(filenames), batch_size):
                batch_filenames = filenames[i:i+batch_size]
                
                # Prepare batch of images
                batch_images = []
                valid_filenames = []
                
                for filename in batch_filenames:
                    img_path = os.path.join('uploads', filename)
                    if os.path.exists(img_path):
                        try:
                            image = Image.open(img_path).convert('RGB')
                            image_tensor = transform(image)
                            batch_images.append(image_tensor)
                            valid_filenames.append(filename)
                        except Exception as e:
                            logger.error(f"Error processing image {filename}: {str(e)}")
                            batch_predictions[filename] = []
                    else:
                        logger.warning(f"Image file not found: {img_path}")
                        batch_predictions[filename] = []
                
                if not batch_images:
                    # No valid images in this batch
                    for filename in batch_filenames:
                        if filename not in batch_predictions:
                            batch_predictions[filename] = []
                    continue
                
                # Stack images into a batch tensor
                batch_tensor = torch.stack(batch_images).to(device)
                
                # Get batch predictions
                with torch.no_grad():
                    batch_outputs = model(batch_tensor)
                    batch_predictions_np = batch_outputs.cpu().numpy()
                
                # Process results for each image in the batch
                for j, filename in enumerate(valid_filenames):
                    predictions = batch_predictions_np[j]
                    results = []
                    
                    for k, (class_name, confidence) in enumerate(zip(class_names, predictions)):
                        if confidence > 0.5:  # Confidence threshold
                            logger.info(f"FewShot prediction for {filename}: class={class_name}, conf={confidence:.2f}")
                            
                            results.append({
                                'label': class_name,
                                'confidence': float(confidence),
                                'source': 'ai',
                            })
                    
                    batch_predictions[filename] = results
                    logger.info(f"Generated {len(results)} FewShot predictions for {filename}")
            
            # Ensure all requested filenames have results
            for filename in filenames:
                if filename not in batch_predictions:
                    batch_predictions[filename] = []
            
            logger.info(f"FewShot batch prediction completed for {len(filenames)} images")
            return batch_predictions
            
        except Exception as e:
            logger.error(f"Error in FewShot batch prediction: {str(e)}", exc_info=True)
            return {filename: [] for filename in filenames}

    @staticmethod
    def predict(filename):
        """Make predictions for an image (backwards compatibility)"""
        try:
            logger.info(f"Making single FewShot prediction for {filename}")
            
            # Use batch prediction with single image
            batch_results = FewShotModelTrainer.predict_batch([filename])
            return batch_results.get(filename, [])
            
        except Exception as e:
            logger.error(f"Error making FewShot predictions: {str(e)}", exc_info=True)
            return []

    @staticmethod
    def reset():
        global MODEL_AVAILABLE, MODEL_READY
        with LOCK:
            MODEL_AVAILABLE = False
            MODEL_READY = False
        # Clear cached model
        FewShotModelTrainer._cached_model = None
        FewShotModelTrainer._cached_class_names = None
        FewShotModelTrainer._cached_transform = None
        FewShotModelTrainer._cached_device = None
        logger.info("Reset FewShot model and cleared cache")

# Initialize the model flags at startup
if os.path.exists(MODEL_PATH):
    MODEL_AVAILABLE = True
    MODEL_READY = True
    logger.info("FewShot model found at startup, setting as ready for predictions") 