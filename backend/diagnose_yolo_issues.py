#!/usr/bin/env python3
"""
YOLO Training Issues Diagnostic Script
This script analyzes your YOLO training setup and identifies issues causing poor predictions.
"""

import os
import json
import pandas as pd
from PIL import Image
import yaml
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def diagnose_yolo_issues():
    """Comprehensive diagnosis of YOLO training issues"""
    
    print("🔍 YOLO Training Issues Diagnostic Report")
    print("=" * 60)
    
    issues_found = []
    recommendations = []
    
    # 1. Check class mapping consistency
    print("\n1. 📊 CLASS MAPPING ANALYSIS")
    print("-" * 30)
    
    classes_json_path = 'model/classes.json'
    dataset_yaml_path = 'datasets/dataset.yaml'
    
    if os.path.exists(classes_json_path):
        with open(classes_json_path, 'r') as f:
            classes_json = json.load(f)
        print(f"✓ Classes.json: {classes_json}")
        num_classes_json = len(classes_json)
    else:
        print("❌ model/classes.json not found")
        issues_found.append("Missing model/classes.json file")
        return
    
    if os.path.exists(dataset_yaml_path):
        with open(dataset_yaml_path, 'r') as f:
            dataset_yaml = yaml.safe_load(f)
        print(f"✓ Dataset.yaml: {dataset_yaml.get('names', [])}")
        num_classes_yaml = dataset_yaml.get('nc', 0)
        names_yaml = dataset_yaml.get('names', [])
    else:
        print("❌ datasets/dataset.yaml not found")
        issues_found.append("Missing datasets/dataset.yaml file")
        return
    
    # Check consistency
    if num_classes_json != num_classes_yaml:
        issues_found.append(f"Class count mismatch: classes.json has {num_classes_json} classes, dataset.yaml has {num_classes_yaml}")
        recommendations.append("Fix class mapping consistency between files")
    
    if len(names_yaml) != num_classes_yaml:
        issues_found.append(f"Dataset.yaml nc={num_classes_yaml} but names has {len(names_yaml)} items")
    
    # 2. Analyze dataset size
    print("\n2. 📈 DATASET SIZE ANALYSIS")
    print("-" * 30)
    
    train_images = 'datasets/train/images'
    val_images = 'datasets/val/images'
    train_labels = 'datasets/train/labels'
    val_labels = 'datasets/val/labels'
    
    train_img_count = len(os.listdir(train_images)) if os.path.exists(train_images) else 0
    val_img_count = len(os.listdir(val_images)) if os.path.exists(val_images) else 0
    train_label_count = len(os.listdir(train_labels)) if os.path.exists(train_labels) else 0
    val_label_count = len(os.listdir(val_labels)) if os.path.exists(val_labels) else 0
    
    print(f"Training images: {train_img_count}")
    print(f"Training labels: {train_label_count}")
    print(f"Validation images: {val_img_count}")
    print(f"Validation labels: {val_label_count}")
    
    total_images = train_img_count + val_img_count
    
    if total_images < 100:
        issues_found.append(f"Dataset too small: only {total_images} total images (recommend 500+ per class)")
        recommendations.append("Collect more training data or use data augmentation")
    
    if train_img_count != train_label_count:
        issues_found.append(f"Image/label mismatch in training: {train_img_count} images vs {train_label_count} labels")
    
    if val_img_count != val_label_count:
        issues_found.append(f"Image/label mismatch in validation: {val_img_count} images vs {val_label_count} labels")
    
    # 3. Analyze label files
    print("\n3. 🏷️ LABEL FILE ANALYSIS")
    print("-" * 30)
    
    def analyze_labels(label_dir, dataset_type):
        if not os.path.exists(label_dir):
            return
            
        label_files = [f for f in os.listdir(label_dir) if f.endswith('.txt')]
        total_annotations = 0
        class_distribution = {}
        
        for label_file in label_files:
            label_path = os.path.join(label_dir, label_file)
            try:
                with open(label_path, 'r') as f:
                    lines = f.readlines()
                    for line in lines:
                        if line.strip():
                            parts = line.strip().split()
                            if len(parts) >= 5:
                                class_id = int(parts[0])
                                class_distribution[class_id] = class_distribution.get(class_id, 0) + 1
                                total_annotations += 1
            except Exception as e:
                issues_found.append(f"Error reading label file {label_file}: {str(e)}")
        
        print(f"{dataset_type} annotations: {total_annotations}")
        print(f"{dataset_type} class distribution: {class_distribution}")
        
        # Check for class ID issues
        expected_classes = set(range(num_classes_json))
        found_classes = set(class_distribution.keys())
        
        if found_classes != expected_classes:
            issues_found.append(f"{dataset_type}: Found class IDs {found_classes}, expected {expected_classes}")
    
    analyze_labels(train_labels, "Training")
    analyze_labels(val_labels, "Validation")
    
    # 4. Analyze training results
    print("\n4. 📊 TRAINING RESULTS ANALYSIS")
    print("-" * 30)
    
    results_path = 'model/training/results.csv'
    if os.path.exists(results_path):
        try:
            df = pd.read_csv(results_path)
            
            # Get final metrics
            final_epoch = df.iloc[-1]
            print(f"Final precision: {final_epoch.get('metrics/precision(B)', 'N/A'):.4f}")
            print(f"Final recall: {final_epoch.get('metrics/recall(B)', 'N/A'):.4f}")
            print(f"Final mAP50: {final_epoch.get('metrics/mAP50(B)', 'N/A'):.4f}")
            print(f"Final mAP50-95: {final_epoch.get('metrics/mAP50-95(B)', 'N/A'):.4f}")
            
            # Check for training issues
            precision_values = df['metrics/precision(B)'].dropna()
            if len(precision_values) > 0:
                avg_precision = precision_values.mean()
                if avg_precision < 0.5:
                    issues_found.append(f"Low precision (avg: {avg_precision:.3f}) indicates many false positives")
                    recommendations.append("Increase confidence threshold, reduce learning rate, or collect more diverse negative examples")
            
            # Check for overfitting
            val_loss = df['val/box_loss'].dropna()
            if len(val_loss) > 5:
                if val_loss.iloc[-1] > val_loss.iloc[-5]:
                    issues_found.append("Validation loss increasing - possible overfitting")
                    recommendations.append("Use early stopping, reduce model complexity, or add more data")
                    
        except Exception as e:
            print(f"Error reading results.csv: {str(e)}")
    else:
        print("❌ No training results found")
    
    # 5. Check training configuration
    print("\n5. ⚙️ TRAINING CONFIGURATION ANALYSIS")
    print("-" * 30)
    
    args_path = 'model/training/args.yaml'
    if os.path.exists(args_path):
        with open(args_path, 'r') as f:
            args = yaml.safe_load(f)
        
        batch_size = args.get('batch', 32)
        epochs = args.get('epochs', 20)
        lr0 = args.get('lr0', 0.01)
        
        print(f"Batch size: {batch_size}")
        print(f"Epochs: {epochs}")
        print(f"Learning rate: {lr0}")
        
        if batch_size > total_images:
            issues_found.append(f"Batch size ({batch_size}) larger than dataset ({total_images})")
            recommendations.append(f"Reduce batch size to {min(4, total_images)}")
        
        if total_images < 50 and epochs < 50:
            issues_found.append(f"Small dataset ({total_images} images) needs more epochs than {epochs}")
            recommendations.append("Increase epochs to 50-100 for small datasets")
        
        if lr0 > 0.001 and total_images < 50:
            issues_found.append(f"Learning rate ({lr0}) too high for small dataset")
            recommendations.append("Reduce learning rate to 0.001 or lower")
    
    # 6. Check model files
    print("\n6. 🤖 MODEL FILES ANALYSIS")
    print("-" * 30)
    
    model_paths = [
        'model/last.pt',
        'model/training/weights/best.pt',
        'model/training/weights/last.pt'
    ]
    
    for path in model_paths:
        if os.path.exists(path):
            size_mb = os.path.getsize(path) / (1024 * 1024)
            print(f"✓ {path}: {size_mb:.1f} MB")
        else:
            print(f"❌ {path}: Not found")
    
    # Summary Report
    print("\n" + "=" * 60)
    print("🚨 ISSUES SUMMARY")
    print("=" * 60)
    
    if issues_found:
        for i, issue in enumerate(issues_found, 1):
            print(f"{i}. {issue}")
    else:
        print("✅ No major issues detected!")
    
    print("\n" + "=" * 60)
    print("💡 RECOMMENDATIONS")
    print("=" * 60)
    
    if recommendations:
        for i, rec in enumerate(recommendations, 1):
            print(f"{i}. {rec}")
    
    # Additional generic recommendations
    print(f"{len(recommendations) + 1}. Consider using a pre-trained model and fine-tuning instead of training from scratch")
    print(f"{len(recommendations) + 2}. Implement data augmentation to increase effective dataset size")
    print(f"{len(recommendations) + 3}. Use a higher confidence threshold (0.3-0.5) during inference")
    print(f"{len(recommendations) + 4}. Collect at least 100-500 images per class for better performance")
    
    return issues_found, recommendations

if __name__ == "__main__":
    issues, recommendations = diagnose_yolo_issues()
    
    print(f"\n🎯 Found {len(issues)} issues and {len(recommendations)} recommendations")
    print("Run this script regularly to monitor your training setup.") 