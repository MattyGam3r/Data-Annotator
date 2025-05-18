import os
import numpy as np
from PIL import Image
import albumentations as A
from albumentations.pytorch import ToTensorV2
import logging
import gc
import json

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ImageAugmenter:
    @staticmethod
    def get_augmentation_pipeline():
        """Create an augmentation pipeline using Albumentations"""
        logger.info("Creating augmentation pipeline")
        return A.Compose([
            A.RandomBrightnessContrast(p=0.5),
            A.RandomGamma(p=0.5),
            A.HueSaturationValue(p=0.5),
            A.RandomRotate90(p=0.5),
            A.HorizontalFlip(p=0.5),
            A.VerticalFlip(p=0.5),
            A.ShiftScaleRotate(shift_limit=0.0625, scale_limit=0.1, rotate_limit=45, p=0.5),
            A.OneOf([
                A.GaussNoise(p=0.5),
                A.GaussianBlur(p=0.5),
                A.MotionBlur(p=0.5),
            ], p=0.3),  # Reduced probability
            # Removed heavier transformations to save memory
        ], bbox_params=A.BboxParams(format='yolo', label_fields=['class_labels'], min_visibility=0.1))

    @staticmethod
    def augment_image(image_path, bboxes, class_labels, output_path, label_path, augmentation_pipeline):
        """Apply augmentation to a single image and its annotations"""
        try:
            logger.info(f"Starting augmentation for image: {image_path}")
            
            # Read image with PIL and convert to numpy array efficiently
            with Image.open(image_path) as img:
                image = np.array(img)
            
            logger.info(f"Image shape: {image.shape}")
            
            # Convert bboxes to list of [x_center, y_center, width, height]
            logger.info("Processing bounding boxes")
            bboxes_list = []
            for box in bboxes:
                x, y, w, h = box
                # Ensure coordinates are within valid range [0, 1]
                x = max(0.0, min(1.0, x))
                y = max(0.0, min(1.0, y))
                w = max(0.0, min(1.0, w))
                h = max(0.0, min(1.0, h))
                bboxes_list.append([x, y, w, h])
            
            logger.info(f"Number of bounding boxes: {len(bboxes_list)}")
            
            # Apply augmentation
            logger.info("Applying augmentation pipeline")
            augmented = augmentation_pipeline(image=image, bboxes=bboxes_list, class_labels=class_labels)
            
            # Ensure the augmented image is valid
            if augmented['image'].size == 0:
                raise ValueError("Augmented image is empty")
            
            logger.info(f"Augmented image shape: {augmented['image'].shape}")
            logger.info(f"Number of augmented bounding boxes: {len(augmented['bboxes'])}")
            
            # Save augmented image efficiently
            logger.info(f"Saving augmented image to: {output_path}")
            with Image.fromarray(augmented['image']) as aug_img:
                aug_img.save(output_path)
            
            # Save augmented annotations
            logger.info(f"Saving annotations to: {label_path}")
            with open(label_path, 'w') as f:
                for box, class_label in zip(augmented['bboxes'], augmented['class_labels']):
                    x, y, w, h = box
                    # Ensure coordinates are within valid range [0, 1]
                    x = max(0.0, min(1.0, x))
                    y = max(0.0, min(1.0, y))
                    w = max(0.0, min(1.0, w))
                    h = max(0.0, min(1.0, h))
                    # Use the class ID (numeric) directly
                    f.write(f"{class_label} {x} {y} {w} {h}\n")
            
            # Explicitly clean up to free memory
            del augmented
            del image
            gc.collect()
            
            logger.info("Augmentation completed successfully")
            return True
        except Exception as e:
            logger.error(f"Error augmenting image {image_path}: {str(e)}", exc_info=True)
            # Clean up in case of error
            gc.collect()
            return False

    @staticmethod
    def create_augmented_dataset(image_path, bboxes, class_labels, base_output_path, base_label_path, num_augmentations=1):
        """Create multiple augmented versions of an image"""
        try:
            logger.info(f"Starting dataset creation for: {image_path}")
            
            # Ensure input image exists
            if not os.path.exists(image_path):
                raise FileNotFoundError(f"Input image not found: {image_path}")
            
            # Create output directories if they don't exist
            os.makedirs(os.path.dirname(base_output_path), exist_ok=True)
            os.makedirs(os.path.dirname(base_label_path), exist_ok=True)
            
            # Load the same class mapping that YOLO uses
            try:
                with open('model/classes.json', 'r') as f:
                    class_map = json.load(f)
                logger.info(f"Loaded class mapping from model/classes.json: {class_map}")
            except Exception as e:
                logger.error(f"Failed to load class mapping, creating a new one: {str(e)}")
                # Create a temporary class mapping
                unique_labels = list(set(class_labels))
                class_map = {label: idx for idx, label in enumerate(sorted(unique_labels))}
                logger.info(f"Created temporary class mapping: {class_map}")
            
            # Convert string class labels to numeric class IDs for YOLO
            numeric_class_labels = []
            for label in class_labels:
                class_id = class_map.get(label)
                if class_id is None:
                    logger.warning(f"Unknown class label: {label}, defaulting to class 0")
                    class_id = 0
                numeric_class_labels.append(class_id)
            
            logger.info(f"Converted string labels to numeric IDs: {list(zip(class_labels, numeric_class_labels))}")
            
            # Save original image efficiently
            logger.info("Saving original image")
            with Image.open(image_path) as img:
                img.save(base_output_path)
            
            # Save original annotations
            logger.info("Saving original annotations with numeric class IDs")
            with open(base_label_path, 'w') as f:
                for box, class_id in zip(bboxes, numeric_class_labels):
                    x, y, w, h = box
                    # Ensure coordinates are within valid range [0, 1]
                    x = max(0.0, min(1.0, x))
                    y = max(0.0, min(1.0, y))
                    w = max(0.0, min(1.0, w))
                    h = max(0.0, min(1.0, h))
                    f.write(f"{class_id} {x} {y} {w} {h}\n")
            
            # Create augmented versions (reduced from 3 to 1 by default to save memory)
            logger.info("Creating augmented versions")
            augmentation_pipeline = ImageAugmenter.get_augmentation_pipeline()
            successful_augmentations = 0
            
            for aug_idx in range(num_augmentations):
                logger.info(f"Creating augmentation {aug_idx + 1}/{num_augmentations}")
                aug_filename = f"{os.path.splitext(base_output_path)[0]}_aug{aug_idx}{os.path.splitext(base_output_path)[1]}"
                aug_label_path = f"{os.path.splitext(base_label_path)[0]}_aug{aug_idx}{os.path.splitext(base_label_path)[1]}"
                
                if ImageAugmenter.augment_image(
                    image_path,
                    bboxes,
                    numeric_class_labels,  # Use numeric class IDs instead of string labels
                    aug_filename,
                    aug_label_path,
                    augmentation_pipeline
                ):
                    successful_augmentations += 1
                
                # Force garbage collection between augmentations
                gc.collect()
            
            # Clean up
            del augmentation_pipeline
            gc.collect()
            
            logger.info(f"Successfully created {successful_augmentations} augmented versions")
            return successful_augmentations > 0
        except Exception as e:
            logger.error(f"Error creating augmented dataset for {image_path}: {str(e)}", exc_info=True)
            # Clean up in case of error
            gc.collect()
            return False 