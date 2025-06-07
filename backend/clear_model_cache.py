#!/usr/bin/env python3
"""
Clear YOLO model cache to force reload with corrected class mapping
"""

import sys
import os

# Add the current directory to the path so we can import yolo_model
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    from yolo_model import YOLOModel
    
    print("Clearing YOLO model cache...")
    YOLOModel.reset()
    print("✓ Model cache cleared successfully!")
    print("The model will reload with the corrected class mapping on next prediction.")
    
except Exception as e:
    print(f"Error clearing model cache: {str(e)}")
    print("You may need to restart your backend server to clear the cache.") 