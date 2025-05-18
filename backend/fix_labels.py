#!/usr/bin/env python3
"""
Fix label files by ensuring class mapping consistency.
This script is a wrapper around ensure_class_consistency.py.
"""

import sys
import os
import logging
import glob
import shutil

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def delete_all_aug_files():
    """Delete all augmented files to force regeneration."""
    logger.info("Deleting all augmented files")
    
    # Directory paths
    train_images_dir = 'datasets/train/images'
    train_labels_dir = 'datasets/train/labels'
    val_images_dir = 'datasets/val/images'
    val_labels_dir = 'datasets/val/labels'
    
    # Create directories if they don't exist
    for directory in [train_images_dir, train_labels_dir, val_images_dir, val_labels_dir]:
        os.makedirs(directory, exist_ok=True)
    
    # Count of deleted files
    deleted_count = 0
    
    # Delete augmented files from all directories
    for directory in [train_images_dir, train_labels_dir, val_images_dir, val_labels_dir]:
        for filename in glob.glob(f"{directory}/*_aug*"):
            try:
                os.remove(filename)
                logger.info(f"Deleted {filename}")
                deleted_count += 1
            except Exception as e:
                logger.error(f"Error deleting {filename}: {str(e)}")
    
    logger.info(f"Deleted {deleted_count} augmented files")
    return deleted_count

def main():
    """Main function to fix label files."""
    logger.info("Starting label fixing process")
    
    # Delete all augmented files
    delete_all_aug_files()
    
    # Run the class consistency check
    try:
        # Add the current directory to the path
        sys.path.append(os.path.dirname(os.path.abspath(__file__)))
        from ensure_class_consistency import main as ensure_consistency
        
        logger.info("Running class consistency check...")
        ensure_consistency()
        logger.info("Class consistency check completed")
        
        print("\nLabel files have been fixed. Follow these steps to complete the process:")
        print("1. Restart the backend server: docker-compose restart backend")
        print("2. In the UI, re-augment your images if needed")
        print("3. Train the model again")
        
    except Exception as e:
        logger.error(f"Error ensuring class consistency: {str(e)}")
        sys.exit(1)
    
    logger.info("Label fixing process completed successfully")

if __name__ == "__main__":
    main() 