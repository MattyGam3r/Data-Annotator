#!/usr/bin/env python3
"""
Ensure consistency in class mapping across the entire system.

This script:
1. Scans all annotations in the database
2. Creates/updates the class mapping file
3. Updates all label files to use the correct class IDs
4. Updates or creates the dataset.yaml file with correct class information
"""

import os
import json
import sqlite3
import glob
import logging
import shutil
import sys

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def get_all_classes_from_database():
    """Scan all annotations in the database to find all unique classes."""
    all_labels = set()
    try:
        conn = sqlite3.connect('metadata.db')
        cursor = conn.cursor()
        
        # Get all annotations from fully annotated images
        cursor.execute("""
            SELECT annotations FROM images 
            WHERE annotations IS NOT NULL AND is_fully_annotated = 1
        """)
        rows = cursor.fetchall()
        
        for row in rows:
            if row[0]:
                try:
                    annotations = json.loads(row[0])
                    for box in annotations:
                        if box.get('isVerified', False) and 'label' in box:
                            all_labels.add(box['label'])
                except Exception as e:
                    logger.error(f"Error parsing annotations: {str(e)}")
        
        conn.close()
        
        logger.info(f"Found {len(all_labels)} unique classes in database: {sorted(list(all_labels))}")
        return sorted(list(all_labels))
    except Exception as e:
        logger.error(f"Error scanning database for classes: {str(e)}")
        return []

def update_class_mapping(classes):
    """Update or create the class mapping file."""
    if not classes:
        logger.error("No classes found, cannot update class mapping")
        return {}
    
    # Try to load existing mapping
    existing_map = {}
    try:
        with open('model/classes.json', 'r') as f:
            existing_map = json.load(f)
        logger.info(f"Loaded existing class mapping: {existing_map}")
    except Exception as e:
        logger.info(f"No existing class mapping found: {str(e)}")
    
    # Create new mapping preserving existing IDs where possible
    class_map = {}
    
    # First add all existing classes to keep their IDs
    for label, idx in existing_map.items():
        if label in classes:
            class_map[label] = idx
    
    # Then add any new classes
    next_id = max(class_map.values()) + 1 if class_map else 0
    for label in classes:
        if label not in class_map:
            class_map[label] = next_id
            next_id += 1
    
    # Create directory and save the mapping
    os.makedirs('model', exist_ok=True)
    with open('model/classes.json', 'w') as f:
        json.dump(class_map, f, indent=2)
    
    logger.info(f"Updated class mapping: {class_map}")
    return class_map

def create_dataset_yaml(class_map):
    """Create or update the dataset.yaml file."""
    dataset_dir = 'datasets'
    os.makedirs(dataset_dir, exist_ok=True)
    
    # Create class names list in correct order
    class_names = ["" for _ in range(len(class_map))]
    for name, idx in class_map.items():
        class_names[idx] = name
    
    # Create dataset.yaml content
    content = f"""path: {os.path.abspath(dataset_dir)}
train: train/images
val: val/images
nc: {len(class_map)}
names: {class_names}
"""
    
    # Write to file
    with open(os.path.join(dataset_dir, 'dataset.yaml'), 'w') as f:
        f.write(content)
    
    logger.info(f"Created dataset.yaml with {len(class_map)} classes")
    return True

def update_label_files(class_map):
    """Update all label files to use the correct class IDs."""
    if not class_map:
        logger.error("No class mapping available, cannot update label files")
        return 0
    
    # Create reverse mapping for debugging
    reverse_map = {idx: name for name, idx in class_map.items()}
    
    # Get label files
    train_label_dir = 'datasets/train/labels'
    val_label_dir = 'datasets/val/labels'
    
    os.makedirs(train_label_dir, exist_ok=True)
    os.makedirs(val_label_dir, exist_ok=True)
    
    train_label_files = glob.glob(f'{train_label_dir}/*.txt')
    val_label_files = glob.glob(f'{val_label_dir}/*.txt')
    
    all_label_files = train_label_files + val_label_files
    logger.info(f"Found {len(all_label_files)} label files to check")
    
    files_updated = 0
    
    for label_file in all_label_files:
        try:
            logger.info(f"Checking {label_file}")
            with open(label_file, 'r') as f:
                lines = f.readlines()
            
            needs_update = False
            updated_lines = []
            
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 5:
                    try:
                        class_id = int(parts[0])
                        
                        # Check if this class ID is valid
                        if class_id not in reverse_map or class_id >= len(class_map):
                            needs_update = True
                            
                            # For augmented files, try to find original file
                            if '_aug' in label_file:
                                # Extract original file name
                                base_name = os.path.basename(label_file).split('_aug')[0] + '.txt'
                                original_file = os.path.join(os.path.dirname(label_file), base_name)
                                
                                if os.path.exists(original_file):
                                    logger.info(f"Checking original file: {original_file}")
                                    with open(original_file, 'r') as f:
                                        orig_lines = f.readlines()
                                    
                                    # Use the first class from original file if available
                                    if orig_lines:
                                        orig_parts = orig_lines[0].strip().split()
                                        if len(orig_parts) >= 5:
                                            orig_class_id = int(orig_parts[0])
                                            if orig_class_id in reverse_map:
                                                updated_class_id = orig_class_id
                                                logger.info(f"Using class ID {updated_class_id} from original file")
                                                updated_lines.append(f"{updated_class_id} {' '.join(parts[1:])}\n")
                                                continue
                            
                            # Default to class ID 0
                            updated_lines.append(f"0 {' '.join(parts[1:])}\n")
                        else:
                            updated_lines.append(line)
                    except ValueError:
                        logger.warning(f"Invalid class ID in {label_file}: {parts[0]}")
                        needs_update = True
                        updated_lines.append(f"0 {' '.join(parts[1:])}\n")
                else:
                    logger.warning(f"Invalid line format in {label_file}: {line.strip()}")
                    needs_update = True
            
            if needs_update:
                # Create backup
                backup_file = f"{label_file}.bak"
                shutil.copy2(label_file, backup_file)
                
                # Write updated file
                with open(label_file, 'w') as f:
                    f.writelines(updated_lines)
                    
                logger.info(f"Updated {label_file}")
                files_updated += 1
        
        except Exception as e:
            logger.error(f"Error processing {label_file}: {str(e)}")
    
    return files_updated

def main():
    """Main function."""
    logger.info("Starting class consistency check")
    
    # Get all classes from database
    classes = get_all_classes_from_database()
    if not classes:
        logger.error("No classes found in database. Make sure you have fully annotated images.")
        sys.exit(1)
    
    # Update class mapping
    class_map = update_class_mapping(classes)
    if not class_map:
        logger.error("Failed to update class mapping")
        sys.exit(1)
    
    # Create or update dataset.yaml
    if not create_dataset_yaml(class_map):
        logger.error("Failed to create dataset.yaml")
        sys.exit(1)
    
    # Update label files
    files_updated = update_label_files(class_map)
    logger.info(f"Updated {files_updated} label files")
    
    logger.info("Class consistency check completed successfully")

if __name__ == "__main__":
    main() 