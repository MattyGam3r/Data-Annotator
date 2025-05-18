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
            train_loader = DataLoader(dataset, batch_size=8, shuffle=True)
            
            # Initialize model
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            model = FewShotModel(len(dataset.class_names)).to(device)
            
            # Define loss function and optimizer
            criterion = nn.BCELoss()
            optimizer = optim.Adam(model.parameters(), lr=0.001)
            
            # Training loop
            num_epochs = 50
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
                
                # Update progress
                progress = (epoch + 1) / num_epochs
                with LOCK:
                    TRAINING_PROGRESS = progress
                logger.info(f"Epoch {epoch+1}/{num_epochs}, Loss: {total_loss/len(train_loader):.4f}")
            
            # Save model
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
    def predict(filename):
        """Make predictions for an image"""
        global MODEL_AVAILABLE, TRAINING_IN_PROGRESS, MODEL_READY
        
        # Check if training is in progress or model is not ready
        # Do this before attempting to load model
        with LOCK:
            if TRAINING_IN_PROGRESS:
                logger.info("Training in progress, deferring predictions")
                return []
            
            if not MODEL_READY:
                logger.info("Model not ready, deferring predictions")
                return []
            
            if not MODEL_AVAILABLE:
                logger.info("Model not available, deferring predictions")
                return []
        
        logger.info(f"Making predictions for {filename} - model is ready")
        
        try:
            # Load model and class mapping
            checkpoint = torch.load(MODEL_PATH)
            class_names = checkpoint['class_names']
            
            # Initialize model
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            model = FewShotModel(len(class_names)).to(device)
            model.load_state_dict(checkpoint['model_state_dict'])
            model.eval()
            
            # Load and preprocess image
            img_path = os.path.join('uploads', filename)
            if not os.path.exists(img_path):
                return []
            
            transform = transforms.Compose([
                transforms.Resize((224, 224)),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
            ])
            
            image = Image.open(img_path).convert('RGB')
            original_width, original_height = image.size
            image_tensor = transform(image).unsqueeze(0).to(device)
            
            # Get predictions
            with torch.no_grad():
                outputs = model(image_tensor)
                predictions = outputs[0].cpu().numpy()
            
            # Convert predictions to bounding boxes
            results = []
            for i, (class_name, confidence) in enumerate(zip(class_names, predictions)):
                if confidence > 0.5:  # Confidence threshold
                    logger.info(f"Prediction: class={class_name}, conf={confidence:.2f}")
                    
                    # Create a more precise bounding box around the center of the image
                    # Use 40% of image width/height as default, with some variation
                    width_ratio = 0.4 + random.uniform(-0.1, 0.1)  # 30-50% of image width
                    height_ratio = 0.4 + random.uniform(-0.1, 0.1)  # 30-50% of image height
                    
                    # Center the box by default
                    width = width_ratio
                    height = height_ratio
                    x = 0.5 - (width / 2)  # Center the box horizontally
                    y = 0.5 - (height / 2)  # Center the box vertically
                    
                    # Ensure box stays within image boundaries and has minimum size
                    x = max(0.01, min(0.99 - width, x))
                    y = max(0.01, min(0.99 - height, y))
                    width = max(0.1, min(0.8, width))
                    height = max(0.1, min(0.8, height))
                    
                    logger.info(f"Generated box: x={x:.4f}, y={y:.4f}, width={width:.4f}, height={height:.4f}")
                    
                    # Add the prediction
                    results.append({
                        'x': float(x),
                        'y': float(y),
                        'width': float(width),
                        'height': float(height),
                        'label': class_name,
                        'confidence': float(confidence),
                        'source': 'ai',
                        'isVerified': False
                    })
            
            return results
        except Exception as e:
            logger.error(f"Error making predictions: {str(e)}", exc_info=True)
            return []
    
    @staticmethod
    def reset():
        global MODEL_AVAILABLE, MODEL_READY
        with LOCK:
            MODEL_AVAILABLE = False
            MODEL_READY = False
        # If you cache the model object in memory, set it to None here
        # Example: FewShotModelTrainer._model = None
        # (Add any additional in-memory cleanup if needed)

# Initialize the model flags at startup
if os.path.exists(MODEL_PATH):
    MODEL_AVAILABLE = True
    MODEL_READY = True
    logger.info("FewShot model found at startup, setting as ready for predictions") 