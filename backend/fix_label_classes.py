#!/usr/bin/env python3
"""
Fix class mapping issues in the YOLO dataset.

This script checks for class mapping inconsistencies between the class mapping file
and the label files, and fixes any issues found.
"""

import os
import json
import logging
import glob

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def check_and_create_class_mapping():
    """Check the current dataset and create a master class mapping if needed."""
    class_map = {}
    
    try:
        # First try to load the existing class mapping
        try:
            with open('model/classes.json', 'r') as f:
                class_map = json.load(f)
            logger.info(f"Loaded existing class mapping: {class_map}")
        except Exception as e:
            logger.warning(f"No existing class mapping found: {str(e)}")
            
        # Scan all label files to discover all classes
        all_labels = set()
        
        # Check train labels
        train_label_files = glob.glob('datasets/train/labels/*.txt')
        val_label_files = glob.glob('datasets/val/labels/*.txt')
        
        all_label_files = train_label_files + val_label_files
        logger.info(f"Scanning {len(all_label_files)} label files for classes")
        
        # Also scan annotations in the database
        import sqlite3
        try:
            conn = sqlite3.connect('metadata.db')
            cursor = conn.cursor()
            cursor.execute("SELECT annotations FROM images WHERE annotations IS NOT NULL")
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
            logger.info(f"Found {len(all_labels)} unique class labels in database")
        except Exception as e:
            logger.error(f"Error scanning database: {str(e)}")
        
        # Create a new class mapping if needed
        if not class_map or set(class_map.keys()) != all_labels:
            # If we have some classes already, keep their existing mappings
            old_map = class_map.copy()
            class_map = {}
            
            # First, preserve existing mappings for classes we already know
            for label in all_labels:
                if label in old_map:
                    class_map[label] = old_map[label]
            
            # Then assign new IDs to any new classes
            next_id = max(class_map.values()) + 1 if class_map else 0
            for label in all_labels:
                if label not in class_map:
                    class_map[label] = next_id
                    next_id += 1
            
            # Save the updated class mapping
            os.makedirs('model', exist_ok=True)
            with open('model/classes.json', 'w') as f:
                json.dump(class_map, f)
            logger.info(f"Created/updated class mapping: {class_map}")
        
        # Create reverse mapping
        reverse_map = {idx: name for name, idx in class_map.items()}
        return class_map, reverse_map
        
    except Exception as e:
        logger.error(f"Error creating class mapping: {str(e)}")
        return {}, {}

def check_label_files(class_map, reverse_map):
    """Check label files for class mapping issues."""
    if not class_map:
        logger.error("No class mapping available, cannot check label files")
        return
    
    # Get number of classes
    num_classes = len(class_map)
    logger.info(f"Number of classes: {num_classes}")
    
    # Check train labels
    train_label_files = glob.glob('datasets/train/labels/*.txt')
    val_label_files = glob.glob('datasets/val/labels/*.txt')
    
    all_label_files = train_label_files + val_label_files
    logger.info(f"Found {len(all_label_files)} label files to check")
    
    issues_found = 0
    files_fixed = 0
    
    for label_file in all_label_files:
        logger.info(f"Checking {label_file}")
        try:
            with open(label_file, 'r') as f:
                lines = f.readlines()
            
            has_issues = False
            fixed_lines = []
            
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 5:
                    try:
                        class_id = int(parts[0])
                        if class_id >= num_classes:
                            logger.warning(f"Class ID {class_id} exceeds dataset class count {num_classes} in {label_file}")
                            has_issues = True
                            
                            # Try to fix by finding the label in the original file
                            if 'aug' in label_file:
                                # This is an augmented file, check the original file
                                original_file = label_file.replace('_aug', '').split('_aug')[0] + '.txt'
                                if os.path.exists(original_file):
                                    logger.info(f"Checking original file {original_file} for reference")
                                    try:
                                        with open(original_file, 'r') as orig_f:
                                            orig_lines = orig_f.readlines()
                                        
                                        # We'll use the first class from the original file as a fallback
                                        if orig_lines:
                                            orig_parts = orig_lines[0].strip().split()
                                            if len(orig_parts) >= 5:
                                                fixed_class_id = int(orig_parts[0])
                                                if fixed_class_id < num_classes:
                                                    logger.info(f"Using class ID {fixed_class_id} from original file")
                                                    fixed_line = f"{fixed_class_id} {parts[1]} {parts[2]} {parts[3]} {parts[4]}\n"
                                                    fixed_lines.append(fixed_line)
                                                    continue
                                    except Exception as e:
                                        logger.error(f"Error checking original file: {str(e)}")
                            
                            # Default to class 0 if we couldn't find a reference
                            logger.info(f"Defaulting to class ID 0")
                            fixed_line = f"0 {parts[1]} {parts[2]} {parts[3]} {parts[4]}\n"
                            fixed_lines.append(fixed_line)
                        else:
                            # Line is fine, keep it as is
                            fixed_lines.append(line)
                    except ValueError:
                        logger.warning(f"Invalid class ID in {label_file}: {parts[0]}")
                        has_issues = True
                        fixed_lines.append(f"0 {parts[1]} {parts[2]} {parts[3]} {parts[4]}\n")
                else:
                    logger.warning(f"Invalid line format in {label_file}: {line.strip()}")
                    has_issues = True
            
            if has_issues:
                issues_found += 1
                
                # Create backup
                backup_file = f"{label_file}.bak"
                import shutil
                shutil.copy2(label_file, backup_file)
                logger.info(f"Created backup: {backup_file}")
                
                # Write fixed file
                with open(label_file, 'w') as f:
                    f.writelines(fixed_lines)
                logger.info(f"Fixed {label_file}")
                files_fixed += 1
        
        except Exception as e:
            logger.error(f"Error processing {label_file}: {str(e)}")
    
    return issues_found, files_fixed

def update_dataset_yaml():
    """Update the dataset.yaml file with the correct class names."""
    class_map, _ = check_and_create_class_mapping()
    if not class_map:
        logger.error("No class mapping available, cannot update dataset.yaml")
        return False
    
    try:
        # Read existing dataset.yaml file
        dataset_yaml_path = 'datasets/dataset.yaml'
        if not os.path.exists(dataset_yaml_path):
            logger.error(f"Dataset config file not found: {dataset_yaml_path}")
            return False
        
        with open(dataset_yaml_path, 'r') as f:
            lines = f.readlines()
        
        # Find the 'names:' line and replace it
        new_lines = []
        names_found = False
        
        for line in lines:
            if line.startswith('names:'):
                names_found = True
                sorted_names = [name for name, _ in sorted(class_map.items(), key=lambda x: x[1])]
                new_lines.append(f"names: {sorted_names}\n")
            else:
                new_lines.append(line)
        
        if not names_found:
            # If 'names:' line was not found, add it
            sorted_names = [name for name, _ in sorted(class_map.items(), key=lambda x: x[1])]
            new_lines.append(f"names: {sorted_names}\n")
        
        # Write updated file
        with open(dataset_yaml_path, 'w') as f:
            f.writelines(new_lines)
        
        logger.info(f"Updated dataset config: {dataset_yaml_path}")
        return True
    
    except Exception as e:
        logger.error(f"Error updating dataset config: {str(e)}")
        return False

if __name__ == "__main__":
    logger.info("Starting label class mapping fix script")
    
    # Check and create class mapping if needed
    class_map, reverse_map = check_and_create_class_mapping()
    
    # Check label files
    issues_found, files_fixed = check_label_files(class_map, reverse_map)
    logger.info(f"Found {issues_found} files with issues, fixed {files_fixed} files")
    
    # Update dataset.yaml
    if update_dataset_yaml():
        logger.info("Dataset configuration updated successfully")
    else:
        logger.error("Failed to update dataset configuration")
    
    logger.info("Script completed") 