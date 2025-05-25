import os
import sqlite3
import json
from flask import Flask, jsonify, Response, request, render_template, send_from_directory
from flask_cors import CORS, cross_origin
from werkzeug import utils
from yolo_model import YOLOModel
from few_shot_model import FewShotModelTrainer
from image_augmenter import ImageAugmenter
import logging
import shutil
import subprocess
from PIL import Image
from threading import Thread
import time
import io
import zipfile

app = Flask(__name__)
cors = CORS(app, 
            origins=["http://localhost:8080", "localhost:8080", "http://localhost:5001", "localhost:5001"],
            methods=["POST", "OPTIONS", "GET"],
            allow_headers=["Content-Type"])

#Store Uploads Here:
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

#Sqlite database to hold the images
DATABASE = 'metadata.db'

logger = logging.getLogger(__name__)

def init_db():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            upload_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            annotations TEXT,
            yolo_predictions TEXT,
            one_shot_predictions TEXT,
            is_fully_annotated BOOLEAN DEFAULT 0,
            uncertainty_score FLOAT DEFAULT NULL,
            UNIQUE (filename)
        );
    ''')
    conn.commit()
    conn.close()

init_db()

@app.route("/")
def home():
    return jsonify({"message": "Hello from Flask!"})


@app.route("/upload", methods=["POST"])
def upload_image():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    imagefiles = request.files.getlist('image')
    #TODO: Get secure filename eventually
    #filename = werkzeug.utils.secure_filename(imagefile.filename)
    for file in imagefiles:
        file.save("./uploads/" + file.filename)
        #Insert the image into the database
        c.execute("INSERT OR IGNORE INTO images (filename) VALUES (?)", (file.filename,))
    conn.commit()
    conn.close()
    response = jsonify({
        "message": "Image(s) Uploaded Successfully"
    })
    return response

#This function returns all images to the user
@app.route("/images", methods=["GET"])
def get_images():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT filename, upload_time, annotations, yolo_predictions, one_shot_predictions, is_fully_annotated, uncertainty_score FROM images")
    rows = c.fetchall()
    data = []
    for row in rows:
        try:
            # Parse annotations and predictions if they exist
            annotations = None
            yolo_predictions = None
            one_shot_predictions = None
            
            if row[2]:  # annotations column
                try:
                    annotations = json.loads(row[2])
                    # Filter out any full-image boxes that were accidentally saved
                    if annotations:
                        annotations = [box for box in annotations if not (
                            box.get('x') == 0.0 and
                            box.get('y') == 0.0 and
                            box.get('width') == 1.0 and
                            box.get('height') == 1.0
                        )]
                except json.JSONDecodeError:
                    annotations = None
                    
            if row[3]:  # yolo_predictions column
                try:
                    yolo_predictions = json.loads(row[3])
                except json.JSONDecodeError:
                    yolo_predictions = None
                    
            if row[4]:  # one_shot_predictions column
                try:
                    one_shot_predictions = json.loads(row[4])
                    # Filter out full-image boxes from few-shot model
                    if one_shot_predictions:
                        one_shot_predictions = [box for box in one_shot_predictions if not (
                            box.get('x') == 0.0 and
                            box.get('y') == 0.0 and
                            box.get('width') == 1.0 and
                            box.get('height') == 1.0
                        )]
                except json.JSONDecodeError:
                    one_shot_predictions = None
            
            image_data = {
                "filename": row[0],
                "upload_time": row[1],
                "annotations": annotations,
                "yolo_predictions": yolo_predictions,
                "one_shot_predictions": one_shot_predictions,
                "isFullyAnnotated": bool(row[5]),
                "uncertainty_score": float(row[6]) if row[6] is not None else None
            }
            print(f"Debug - Sending image data: {image_data}")  # Debug log
            data.append(image_data)
        except Exception as e:
            print(f"Error processing row: {e}")
            continue
    
    conn.close()
    print(f"Debug - Total images being sent: {len(data)}")  # Debug log
    return jsonify(data)

@cross_origin
@app.route("/uploads/<filename>", methods=['GET'])
def get_image(filename):
    return send_from_directory("./uploads/", filename)

@app.route("/save_annotations", methods=["POST"])
def save_annotations():
    print("Debug - Received save_annotations request")  # Debug log
    data = request.json
    filename = data.get('filename')
    annotations = data.get('annotations')
    is_fully_annotated = data.get('isFullyAnnotated', False)
    
    if not filename:
        return jsonify({"error": "Filename is required"}), 400
    
    # Extract just the filename part (remove any URL components)
    filename = filename.split('/')[-1]
    
    print(f"Debug - Filename: {filename}")  # Debug log
    print(f"Debug - Annotations: {annotations}")  # Debug log
    print(f"Debug - Is fully annotated: {is_fully_annotated}")  # Debug log
    
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    
    try:
        # If annotations is empty or None, set it to NULL in the database
        if not annotations:
            if is_fully_annotated:
                c.execute("UPDATE images SET annotations = NULL, is_fully_annotated = ?, uncertainty_score = NULL WHERE filename = ?", 
                         (is_fully_annotated, filename))
            else:
                c.execute("UPDATE images SET annotations = NULL, is_fully_annotated = ? WHERE filename = ?", 
                         (is_fully_annotated, filename))
        else:
            # Convert annotations to JSON string if it's not already
            if not isinstance(annotations, str):
                # Check for verified AI predictions and clear model predictions to prevent duplication
                has_verified_ai = any(box.get('source') == 'ai' and box.get('isVerified', False) 
                                    for box in annotations)
                
                # If user has verified any AI predictions, clear the model predictions columns
                # This ensures they won't reappear when the user comes back to this image
                if has_verified_ai:
                    c.execute("UPDATE images SET yolo_predictions = NULL, one_shot_predictions = NULL WHERE filename = ?",
                             (filename,))
                    print(f"Debug - Cleared model predictions for {filename} to prevent duplication")
                
                annotations = json.dumps(annotations)
                print(f"Debug - Converted annotations to JSON: {annotations}")  # Debug log
            
            if is_fully_annotated:
                c.execute("UPDATE images SET annotations = ?, is_fully_annotated = ?, uncertainty_score = NULL WHERE filename = ?", 
                         (annotations, is_fully_annotated, filename))
            else:
                c.execute("UPDATE images SET annotations = ?, is_fully_annotated = ? WHERE filename = ?", 
                         (annotations, is_fully_annotated, filename))
        
        conn.commit()
        
        if c.rowcount == 0:
            print(f"Debug - No rows updated for filename: {filename}")  # Debug log
            return jsonify({"error": "Image not found"}), 404
            
        print("Debug - Annotations saved successfully")  # Debug log
        return jsonify({"message": "Annotations saved successfully"})
    except Exception as e:
        print(f"Debug - Error saving annotations: {str(e)}")  # Debug log
        print(f"Debug - Error type: {type(e)}")  # Debug log
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route("/model_status", methods=["GET"])
def get_model_status():
    """Get the current status of both models"""
    # Get augmentation status
    train_dir = 'datasets/train/images'
    has_augmentations = False
    num_augmentations = 0
    
    if os.path.exists(train_dir):
        for filename in os.listdir(train_dir):
            if '_aug' in filename:
                has_augmentations = True
                num_augmentations += 1
    
    # Get status for both models
    yolo_status = YOLOModel.get_model_status()
    few_shot_status = FewShotModelTrainer.get_model_status()
    
    status = {
        'yolo': {
            'is_available': yolo_status.get('is_available', False),
            'training_in_progress': yolo_status.get('training_in_progress', False),
            'progress': yolo_status.get('progress', 0.0)
        },
        'few_shot': {
            'is_available': few_shot_status.get('is_available', False),
            'training_in_progress': few_shot_status.get('training_in_progress', False),
            'progress': few_shot_status.get('progress', 0.0)
        },
        'has_augmentations': has_augmentations,
        'num_augmentations': num_augmentations
    }
    
    return jsonify(status)

@app.route("/train_model", methods=["POST"])
def train_model():
    try:
        print("Debug - Starting model training")
        data = request.json
        model_type = data.get('model_type', 'yolo')  # Default to YOLO if not specified
        
        # Get fully annotated images directly from the database
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        # Clear predictions for the model being trained
        if model_type == 'yolo':
            cursor.execute("UPDATE images SET yolo_predictions = NULL")
        else:
            cursor.execute("UPDATE images SET one_shot_predictions = NULL")
        conn.commit()
        
        # Get all fully annotated images with their annotations
        cursor.execute('''
            SELECT filename, upload_time, annotations, is_fully_annotated 
            FROM images 
            WHERE is_fully_annotated = 1
        ''')
        rows = cursor.fetchall()
        
        print(f"Debug - Found {len(rows)} fully annotated images in database")
        
        if not rows:
            print("Debug - No fully annotated images found in database")
            conn.close()
            return jsonify({"error": "No fully annotated images found in database"}), 400
        
        # Convert database rows to training data format
        training_images = []
        for row in rows:
            try:
                filename = row[0]
                upload_time = row[1]
                annotations = json.loads(row[2]) if row[2] else []
                is_fully_annotated = bool(row[3])
                
                print(f"Debug - Processing image: {filename}")
                print(f"Debug - Raw annotations: {row[2]}")
                print(f"Debug - Parsed annotations: {annotations}")
                
                # Log all unique labels in this image
                labels = set()
                for box in annotations:
                    if box.get('isVerified', False):
                        labels.add(box.get('label', ''))
                print(f"Debug - Unique verified labels in {filename}: {labels}")
                
                image_data = {
                    'filename': filename,
                    'upload_time': upload_time,
                    'annotations': annotations,
                    'isFullyAnnotated': is_fully_annotated
                }
                training_images.append(image_data)
                
            except Exception as e:
                print(f"Error processing image {row[0]}: {str(e)}")
                continue
        
        conn.close()
        
        if not training_images:
            print("Debug - No valid training images after processing")
            return jsonify({"error": "No valid training images found"}), 400
        
        # Log summary of all classes in training data
        all_classes = set()
        for img in training_images:
            for box in img.get('annotations', []):
                if box.get('isVerified', False):
                    all_classes.add(box.get('label', ''))
        print(f"Debug - All classes in training data: {all_classes}")
        print(f"Debug - Prepared {len(training_images)} images for training")
        
        # Save training data
        with open('training_data.json', 'w') as f:
            json.dump(training_images, f)
        
        # Start training in a separate thread
        def train_and_predict():
            try:
                # Train the model
                if model_type == 'yolo':
                    model_module = YOLOModel
                else:
                    model_module = FewShotModelTrainer
                    
                # Start training and wait for it to complete
                model_module.start_training(training_images)
                
                # Wait for training to complete and model to be available and ready
                print("Debug - Waiting for training to complete")
                attempts = 0
                max_attempts = 600  # Maximum 10 minutes of waiting (600 seconds)
                
                while attempts < max_attempts:
                    # Get current status
                    status = model_module.get_model_status()
                    print(f"Debug - Training status: {status}")
                    
                    # Check if training is complete AND model is available AND ready
                    if (not status['training_in_progress'] and 
                        status['is_available'] and 
                        status['is_ready']):
                        print("Debug - Training complete and model ready")
                        break
                        
                    time.sleep(2)  # Check every 2 seconds
                    attempts += 1
                
                if attempts >= max_attempts:
                    print("Debug - Timed out waiting for training to complete")
                    # Force the model to be ready if timeout exceeded
                    with model_module.LOCK:
                        model_module.MODEL_READY = True
                    print("Debug - Forced model ready status to True")
                
                # Extra wait to ensure model is fully loaded and filesystem is synced
                time.sleep(5)
                
                # Verify one more time that model is ready
                status = model_module.get_model_status()
                if not status['is_ready']:
                    print("Debug - Model still not ready after waiting, forcing ready state")
                    with model_module.LOCK:
                        model_module.MODEL_READY = True
                
                print("Debug - Starting predictions with the newly trained model")
                
                # After training is complete and model is available, predict for all non-complete images
                conn = sqlite3.connect(DATABASE)
                cursor = conn.cursor()
                
                # Get all non-complete images
                cursor.execute('SELECT filename FROM images WHERE is_fully_annotated = 0')
                non_complete_images = cursor.fetchall()
                print(f"Debug - Found {len(non_complete_images)} non-complete images")
                
                # Get predictions for each non-complete image
                for (filename,) in non_complete_images:
                    try:
                        print(f"Debug - Getting predictions for {filename}")
                        # Get predictions using the appropriate model
                        if model_type == 'yolo':
                            # Explicitly use the newly trained model
                            predictions = YOLOModel.predict(filename, use_latest=True)
                            column = 'yolo_predictions'
                        else:
                            predictions = FewShotModelTrainer.predict(filename)
                            column = 'one_shot_predictions'
                            
                        print(f"Debug - Got {len(predictions)} predictions for {filename}")
                        
                        # Convert predictions to handle numpy types
                        def convert_numpy_types(obj):
                            import numpy as np
                            if isinstance(obj, dict):
                                return {k: convert_numpy_types(v) for k, v in obj.items()}
                            elif isinstance(obj, list):
                                return [convert_numpy_types(i) for i in obj]
                            elif isinstance(obj, np.integer):
                                return int(obj)
                            elif isinstance(obj, np.floating):
                                return float(obj)
                            elif isinstance(obj, np.ndarray):
                                return convert_numpy_types(obj.tolist())
                            else:
                                return obj
                        
                        # Convert all NumPy types to native Python types
                        predictions = convert_numpy_types(predictions)
                        
                        # Save predictions
                        try:
                            # Check if we can serialize the predictions
                            json_predictions = json.dumps(predictions)
                            print(f"Debug - Successfully serialized {len(predictions)} predictions ({len(json_predictions)} bytes)")
                            
                            # Log a sample prediction
                            if len(predictions) > 0:
                                print(f"Debug - First prediction sample: {json.dumps(predictions[0])}")
                            
                            print(f"Debug - Updating {column} for {filename} with {len(predictions)} predictions")
                            cursor.execute(f'''
                                UPDATE images 
                                SET {column} = ?
                                WHERE filename = ?
                            ''', (json_predictions, filename))
                            
                            # Log row count to see if update was successful
                            print(f"Debug - Database rows affected: {cursor.rowcount}")
                            
                            conn.commit()
                            
                            # Verify the update worked
                            cursor.execute(f"SELECT {column} FROM images WHERE filename = ?", (filename,))
                            result = cursor.fetchone()
                            if result and result[0]:
                                stored_preds = json.loads(result[0])
                                print(f"Debug - Verified {len(stored_preds)} predictions stored in database for {filename}")
                            else:
                                print(f"Debug - WARNING: Failed to store predictions in database for {filename}")
                                
                                # Try a direct SELECT to see what might be in the database
                                cursor.execute(f"SELECT id, filename, {column} FROM images WHERE filename = ?", (filename,))
                                debug_result = cursor.fetchone()
                                if debug_result:
                                    print(f"Debug - Database record: id={debug_result[0]}, filename={debug_result[1]}, has_predictions={bool(debug_result[2])}")
                                else:
                                    print(f"Debug - No record found in database for {filename}")
                                
                        except Exception as json_error:
                            print(f"Debug - Error handling JSON data: {str(json_error)}")
                            
                            # Try to sanitize the predictions
                            sanitized_predictions = []
                            for pred in predictions:
                                # Ensure all values are basic Python types
                                sanitized_pred = {
                                    'x': float(pred.get('x', 0.0)),
                                    'y': float(pred.get('y', 0.0)),
                                    'width': float(pred.get('width', 0.0)),
                                    'height': float(pred.get('height', 0.0)),
                                    'label': str(pred.get('label', '')),
                                    'confidence': float(pred.get('confidence', 0.0)),
                                    'source': 'ai',
                                    'isVerified': False
                                }
                                sanitized_predictions.append(sanitized_pred)
                            
                            # Try serializing again
                            json_predictions = json.dumps(sanitized_predictions)
                            print(f"Debug - Successfully serialized sanitized predictions: {len(json_predictions)} bytes")
                            
                            # Update with sanitized predictions
                            cursor.execute(f'''
                                UPDATE images 
                                SET {column} = ?
                                WHERE filename = ?
                            ''', (json_predictions, filename))
                            conn.commit()
                            
                            print(f"Debug - Stored sanitized predictions in database")
                            
                        print(f"Debug - Saved predictions for {filename}")
                        
                    except Exception as e:
                        print(f"Error processing {filename}: {str(e)}")
                        import traceback
                        traceback.print_exc()
                        continue
                
                # Update uncertainty scores after training
                print("Debug - Updating uncertainty scores for all images")
                for (filename,) in non_complete_images:
                    try:
                        # Get predictions from both models
                        yolo_predictions = YOLOModel.predict(filename)
                        few_shot_predictions = FewShotModelTrainer.predict(filename)
                        
                        # Convert NumPy types to native Python types
                        def convert_numpy_types(obj):
                            import numpy as np
                            if isinstance(obj, dict):
                                return {k: convert_numpy_types(v) for k, v in obj.items()}
                            elif isinstance(obj, list):
                                return [convert_numpy_types(i) for i in obj]
                            elif isinstance(obj, np.integer):
                                return int(obj)
                            elif isinstance(obj, np.floating):
                                return float(obj)
                            elif isinstance(obj, np.ndarray):
                                return convert_numpy_types(obj.tolist())
                            else:
                                return obj
                        
                        yolo_predictions = convert_numpy_types(yolo_predictions)
                        few_shot_predictions = convert_numpy_types(few_shot_predictions)
                        
                        # Calculate uncertainty score
                        uncertainty_score = calculate_uncertainty_score(yolo_predictions, few_shot_predictions)
                        
                        # Update uncertainty score in database
                        cursor.execute('''
                            UPDATE images 
                            SET uncertainty_score = ?
                            WHERE filename = ?
                        ''', (float(uncertainty_score), filename))
                        conn.commit()
                        print(f"Debug - Updated uncertainty score for {filename}: {uncertainty_score}")
                        
                    except Exception as e:
                        print(f"Error updating uncertainty score for {filename}: {str(e)}")
                        continue
                
                conn.close()
                
            except Exception as e:
                print(f"Error in training thread: {str(e)}")
        
        # Start the training thread
        thread = Thread(target=train_and_predict)
        thread.daemon = True
        thread.start()
        
        return jsonify({"message": "Training started successfully"})
        
    except Exception as e:
        print(f"Error in train_model endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/datasets/train/images/<filename>", methods=['GET'])
def get_training_image(filename):
    """Serve images from the training directory"""
    return send_from_directory('datasets/train/images', filename)

@app.route("/get_augmented_images/<filename>", methods=["GET"])
def get_augmented_images(filename):
    """Get all augmented versions of an image"""
    print(f"Getting augmented images for {filename}")
    conn = None
    try:
        # Get the base image path
        base_path = os.path.join('uploads', filename)
        if not os.path.exists(base_path):
            print(f"Base image not found at {base_path}")
            return jsonify({"error": "Image not found"}), 404
            
        # Get all augmented versions
        augmented_images = []
        
        # Add the original image with its annotations
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        c.execute("SELECT annotations FROM images WHERE filename = ?", (filename,))
        row = c.fetchone()
        original_annotations = row[0] if row else None
        print(f"Original annotations: {original_annotations}")
        
        augmented_images.append({
            'url': f'/uploads/{filename}',
            'is_original': True,
            'annotations': original_annotations
        })
        
        # Look for augmented versions in the training dataset
        train_dir = 'datasets/train/images'
        labels_dir = 'datasets/train/labels'
        
        if os.path.exists(train_dir) and os.path.exists(labels_dir):
            base_name = os.path.splitext(filename)[0]
            
            for aug_file in os.listdir(train_dir):
                if aug_file.startswith(f"{base_name}_aug") and aug_file.endswith(os.path.splitext(filename)[1]):
                    # Get annotations for the augmented image
                    aug_label_file = os.path.join(labels_dir, os.path.splitext(aug_file)[0] + '.txt')
                    annotations = None
                    
                    if os.path.exists(aug_label_file):
                        boxes = []
                        with open(aug_label_file, 'r') as f:
                            for line in f:
                                try:
                                    parts = line.strip().split()
                                    if len(parts) >= 5:
                                        label = parts[0]
                                        x_center = float(parts[1])
                                        y_center = float(parts[2])
                                        width = float(parts[3])
                                        height = float(parts[4])
                                        
                                        # Convert from YOLO format (center x, center y, width, height)
                                        # to our format (top-left x, top-left y, width, height)
                                        x = x_center - width/2
                                        y = y_center - height/2
                                        
                                        box = {
                                            'x': x,
                                            'y': y,
                                            'width': width,
                                            'height': height,
                                            'label': label,
                                            'source': 'ai',
                                            'confidence': 1.0,
                                            'isVerified': True
                                        }
                                        boxes.append(box)
                                except Exception as e:
                                    print(f"Error parsing line in {aug_label_file}: {str(e)}")
                                    continue
                        if boxes:
                            annotations = json.dumps(boxes)
                    
                    augmented_images.append({
                        'url': f'/datasets/train/images/{aug_file}',
                        'is_original': False,
                        'annotations': annotations
                    })
        
        if conn:
            conn.close()
        return jsonify({"images": augmented_images})
    except Exception as e:
        if conn:
            conn.close()
        print(f"Error in get_augmented_images: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/predict", methods=["POST"])
def predict():
    """Get predictions for an image using the selected model"""
    data = request.json
    filename = data.get('filename')
    model_type = data.get('model_type', 'yolo')
    
    if not filename:
        return jsonify({"error": "Filename is required"}), 400
    
    # Check if model is available or still training
    if model_type == 'yolo':
        status = YOLOModel.get_model_status()
    else:
        status = FewShotModelTrainer.get_model_status()
    
    print(f"Debug - Model status for prediction: {status}")
        
    if status['training_in_progress']:
        print(f"Debug - Prediction requested for {filename} but model is still training")
        return jsonify({"error": "Model is still training, please wait until training is complete", "status": status}), 400
        
    if not status['is_available']:
        print(f"Debug - Prediction requested for {filename} but model is not available")
        return jsonify({"error": "Model is not available. Train a model first.", "status": status}), 400
    
    # Check if model is ready
    if not status.get('is_ready', False):
        print(f"Debug - Prediction requested for {filename} but model is not ready yet")
        
        # Force model ready if model is available but not ready
        if status['is_available'] and not status['training_in_progress']:
            print(f"Debug - Model is available but not ready. Forcing ready state.")
            if model_type == 'yolo':
                with YOLOModel.LOCK:
                    YOLOModel.MODEL_READY = True
            else:
                with FewShotModelTrainer.LOCK:
                    FewShotModelTrainer.MODEL_READY = True
        else:
            return jsonify({"error": "Model training has completed but model is not ready yet. Please wait.", "status": status}), 400
    
    # Get predictions from the selected model
    print(f"Debug - Getting predictions for {filename} using {model_type} model")
    conn = None
    try:
        if model_type == 'few_shot':
            predictions = FewShotModelTrainer.predict(filename)
            column = 'one_shot_predictions'
        else:
            predictions = YOLOModel.predict(filename, use_latest=True)
            column = 'yolo_predictions'
            
        if predictions is None or len(predictions) == 0:
            print(f"Debug - No predictions returned for {filename}, model may still be initializing")
            return jsonify({"predictions": [], "status": "no_predictions"}), 200
    
        # Convert NumPy types to native Python types for JSON serialization
        def convert_numpy_types(obj):
            import numpy as np
            if isinstance(obj, dict):
                return {k: convert_numpy_types(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_numpy_types(i) for i in obj]
            elif isinstance(obj, np.integer):
                return int(obj)
            elif isinstance(obj, np.floating):
                return float(obj)
            elif isinstance(obj, np.ndarray):
                return convert_numpy_types(obj.tolist())
            else:
                return obj
        
        # Convert all NumPy types to native Python types
        predictions = convert_numpy_types(predictions)
        
        # Log prediction results
        print(f"Debug - Got {len(predictions)} predictions for {filename}")
        
        # Ensure filename doesn't have path components
        clean_filename = filename.split('/')[-1]
        print(f"Debug - Using clean filename for DB update: {clean_filename}")
        
        # Store predictions in the database
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        
        # First verify the image exists in the database
        c.execute("SELECT id FROM images WHERE filename = ?", (clean_filename,))
        if not c.fetchone():
            print(f"Warning - Image {clean_filename} not found in database, adding it")
            c.execute("INSERT INTO images (filename) VALUES (?)", (clean_filename,))
        
        # Convert predictions to JSON string
        try:
            # First check if we can serialize the predictions
            json_predictions = json.dumps(predictions)
            print(f"Debug - Successfully serialized predictions to JSON: {len(json_predictions)} bytes")
            
            # Log a sample of the JSON for debugging
            if len(predictions) > 0:
                print(f"Debug - First prediction sample: {json.dumps(predictions[0])}")
            
            # Update predictions in the database
            print(f"Debug - Updating {column} for {clean_filename} with {len(predictions)} predictions")
            c.execute(f"UPDATE images SET {column} = ? WHERE filename = ?", 
                     (json_predictions, clean_filename))
            
            # Log row count to see if update was successful
            print(f"Debug - Database rows affected: {c.rowcount}")
            
            # Commit changes
            conn.commit()
            
            # Verify the update
            c.execute(f"SELECT {column} FROM images WHERE filename = ?", (clean_filename,))
            result = c.fetchone()
            if result and result[0]:
                stored_preds = json.loads(result[0])
                print(f"Debug - Verified predictions stored in database for {clean_filename}: {len(stored_preds)} predictions")
            else:
                print(f"Debug - WARNING: Failed to verify predictions in database for {clean_filename}")
                
                # Try a direct SELECT to see what might be in the database
                c.execute(f"SELECT id, filename, {column} FROM images WHERE filename = ?", (clean_filename,))
                debug_result = c.fetchone()
                if debug_result:
                    print(f"Debug - Database record: id={debug_result[0]}, filename={debug_result[1]}, has_predictions={bool(debug_result[2])}")
                else:
                    print(f"Debug - No record found in database for {clean_filename}")
                    
                    # Check if there are any records in the images table
                    c.execute("SELECT COUNT(*) FROM images")
                    count = c.fetchone()[0]
                    print(f"Debug - Total records in images table: {count}")
                    
                    if count > 0:
                        # Get the first few records to compare filenames
                        c.execute("SELECT id, filename FROM images LIMIT 5")
                        samples = c.fetchall()
                        print(f"Debug - Sample records: {samples}")
            
        except Exception as json_error:
            print(f"Debug - Error handling JSON data: {str(json_error)}")
            print(f"Debug - Problematic predictions object: {type(predictions)}")
            
            # Try to handle specific serialization issues
            sanitized_predictions = []
            try:
                for pred in predictions:
                    # Ensure all values are basic Python types
                    sanitized_pred = {
                        'x': float(pred.get('x', 0.0)),
                        'y': float(pred.get('y', 0.0)),
                        'width': float(pred.get('width', 0.0)),
                        'height': float(pred.get('height', 0.0)),
                        'label': str(pred.get('label', '')),
                        'confidence': float(pred.get('confidence', 0.0)),
                        'source': 'ai',
                        'isVerified': False
                    }
                    sanitized_predictions.append(sanitized_pred)
                
                # Try serializing again
                json_predictions = json.dumps(sanitized_predictions)
                print(f"Debug - Successfully serialized sanitized predictions: {len(json_predictions)} bytes")
                
                # Update with sanitized predictions
                c.execute(f"UPDATE images SET {column} = ? WHERE filename = ?", 
                         (json_predictions, clean_filename))
                conn.commit()
                
                print(f"Debug - Stored sanitized predictions in database")
            except Exception as sanitize_error:
                print(f"Debug - Error sanitizing predictions: {str(sanitize_error)}")
                raise
        
        return jsonify({"predictions": predictions, "status": "success"})
    except Exception as e:
        print(f"Error in prediction: {str(e)}")
        import traceback
        traceback.print_exc()
        
        # If we're in a transaction, roll it back
        if conn:
            try:
                conn.rollback()
            except:
                pass
        return jsonify({"error": str(e), "predictions": []}), 500
    finally:
        # Always close the connection
        if conn:
            try:
                conn.close()
            except:
                pass

@app.route("/mark_complete", methods=["POST"])
def mark_complete():
    """Mark an image as fully annotated"""
    data = request.json
    filename = data.get('filename')
    
    if not filename:
        return jsonify({"error": "Filename is required"}), 400
    
    # Extract just the filename part (remove any URL components)
    filename = filename.split('/')[-1]
    
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    
    try:
        c.execute("UPDATE images SET is_fully_annotated = 1, uncertainty_score = NULL WHERE filename = ?", (filename,))
        conn.commit()
        
        if c.rowcount == 0:
            return jsonify({"error": "Image not found"}), 404
            
        return jsonify({"message": "Image marked as fully annotated"})
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@cross_origin
@app.route("/augment_images", methods=["POST", "OPTIONS"])
def augment_images():
    """Augment all images with verified annotations"""
    logger.info("Received request to /augment_images")
    logger.info(f"Request method: {request.method}")
    logger.info(f"Request headers: {request.headers}")
    
    if request.method == "OPTIONS":
        logger.info("Handling OPTIONS request")
        return jsonify({}), 200
        
    try:
        data = request.get_json()
        logger.info(f"Request data: {data}")
        
        if not data:
            logger.error("No data provided in request")
            return jsonify({"error": "No data provided"}), 400
            
        num_augmentations = data.get('num_augmentations', 1)
        logger.info(f"Number of augmentations requested: {num_augmentations}")
        
        if num_augmentations < 0:
            logger.error("Invalid number of augmentations")
            return jsonify({"error": "Number of augmentations must be greater than or equal to 0"}), 400
        
        # First ensure class mapping consistency
        try:
            logger.info("Running class consistency check before augmentation")
            import sys
            import os
            sys.path.append(os.path.dirname(os.path.abspath(__file__)))
            from ensure_class_consistency import main as ensure_consistency
            ensure_consistency()
            logger.info("Class consistency check completed")
        except Exception as e:
            logger.error(f"Error in class consistency check: {str(e)}")
            return jsonify({"error": f"Error ensuring class mapping consistency: {str(e)}"}), 500
            
        # Get all images with verified annotations
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        c.execute("SELECT filename, annotations FROM images WHERE annotations IS NOT NULL")
        rows = c.fetchall()
        
        if not rows:
            logger.error("No images with annotations found")
            return jsonify({"error": "No images with annotations found"}), 404
            
        # Load class mapping that YOLO uses
        class_map = {}
        try:
            with open('model/classes.json', 'r') as f:
                class_map = json.load(f)
            logger.info(f"Loaded class mapping from model/classes.json: {class_map}")
        except Exception as e:
            logger.warning(f"Failed to load class mapping: {str(e)}, will create one during augmentation")
            
        # Clear existing augmentations
        logger.info("Clearing existing augmentations")
        train_dir = 'datasets/train/images'
        labels_dir = 'datasets/train/labels'
        
        # Clear augmented files from training directory
        if os.path.exists(train_dir):
            for filename in os.listdir(train_dir):
                if '_aug' in filename:  # Only delete augmented files
                    try:
                        os.remove(os.path.join(train_dir, filename))
                        # Also remove corresponding label file
                        label_file = os.path.join(labels_dir, os.path.splitext(filename)[0] + '.txt')
                        if os.path.exists(label_file):
                            os.remove(label_file)
                    except Exception as e:
                        logger.error(f"Error deleting augmented file {filename}: {str(e)}")
        
        # Process each image
        successful_augmentations = 0
        total_images = len(rows)
        logger.info(f"Processing {total_images} images")
        
        for i, (filename, annotations_json) in enumerate(rows):
            try:
                annotations = json.loads(annotations_json)
                verified_boxes = [box for box in annotations if box.get('isVerified', False)]
                
                if not verified_boxes:
                    logger.info(f"No verified boxes found for {filename}")
                    continue
                    
                # Prepare bboxes and class labels for augmentation
                bboxes = []
                class_labels = []
                for box in verified_boxes:
                    x = box.get('x', 0.0)
                    y = box.get('y', 0.0)
                    w = box.get('width', 0.0)
                    h = box.get('height', 0.0)
                    
                    # Convert to center coordinates
                    center_x = x + w/2
                    center_y = y + h/2
                    
                    bboxes.append([center_x, center_y, w, h])
                    class_labels.append(box.get('label', ''))
                
                # Create augmented versions using the existing pipeline
                src_path = os.path.join('uploads', filename)
                base_output_path = os.path.join('datasets/train/images', filename)
                base_label_path = os.path.join('datasets/train/labels', os.path.splitext(filename)[0] + '.txt')
                
                # Create augmented versions
                if ImageAugmenter.create_augmented_dataset(
                    src_path,
                    bboxes,
                    class_labels,
                    base_output_path,
                    base_label_path,
                    num_augmentations=num_augmentations
                ):
                    successful_augmentations += 1
                    logger.info(f"Successfully augmented {filename}")
                    
            except Exception as e:
                logger.error(f"Error augmenting image {filename}: {str(e)}")
                continue
        
        conn.close()
        
        logger.info(f"Augmentation complete. Successfully augmented {successful_augmentations} images")
        return jsonify({
            "success": True,
            "total_images": total_images,
            "successful_augmentations": successful_augmentations
        })
        
    except Exception as e:
        logger.error(f"Error in augment_images: {str(e)}")
        return jsonify({"error": str(e)}), 500

def calculate_uncertainty_score(yolo_preds, few_shot_preds):
    """Calculate uncertainty score based on differences between model predictions"""
    if not yolo_preds and not few_shot_preds:
        return 1.0  # Maximum uncertainty when no predictions
        
    if not yolo_preds or not few_shot_preds:
        return 0.8  # High uncertainty when only one model predicts
    
    # Extract labels from predictions
    yolo_labels = [pred['label'] for pred in yolo_preds]
    
    # For few-shot predictions, we might have either old-style bounding box predictions 
    # or new-style label-only predictions
    if 'x' in few_shot_preds[0] if few_shot_preds else False:
        # Old style - extract labels from bounding boxes
        few_shot_labels = [pred['label'] for pred in few_shot_preds]
    else:
        # New style - directly use labels
        few_shot_labels = [pred['label'] for pred in few_shot_preds]
    
    # Get unique labels from both models
    yolo_label_set = set(yolo_labels)
    few_shot_label_set = set(few_shot_labels)
    all_labels = yolo_label_set.union(few_shot_label_set)
    common_labels = yolo_label_set.intersection(few_shot_label_set)
    
    # Calculate label disagreement ratio
    label_disagreement = 1 - (len(common_labels) / len(all_labels) if all_labels else 0)
    
    # Calculate prediction count difference
    pred_count_diff = abs(len(yolo_labels) - len(few_shot_labels))
    count_disagreement = min(0.2, pred_count_diff * 0.1)  # Cap at 0.2
    
    # Calculate average confidence for each model
    yolo_conf_avg = sum(pred.get('confidence', 0.5) for pred in yolo_preds) / len(yolo_preds) if yolo_preds else 0
    
    # For few-shot confidence calculation, handle both formats
    if 'x' in few_shot_preds[0] if few_shot_preds else False:
        # Old style with bounding boxes
        few_shot_conf_avg = sum(pred.get('confidence', 0.5) for pred in few_shot_preds) / len(few_shot_preds) if few_shot_preds else 0
    else:
        # New style with just labels
        few_shot_conf_avg = sum(pred.get('confidence', 0.5) for pred in few_shot_preds) / len(few_shot_preds) if few_shot_preds else 0
    
    avg_confidence = (yolo_conf_avg + few_shot_conf_avg) / 2
    confidence_uncertainty = 1 - avg_confidence  # Low confidence means high uncertainty
    
    # Calculate final uncertainty score with weighted factors
    uncertainty = (
        0.6 * label_disagreement +  # Increased weight on label disagreement
        0.3 * confidence_uncertainty +  # Increased weight on confidence
        0.1 * count_disagreement  # Reduced weight on count disagreement
    )
    
    return min(1.0, uncertainty)  # Cap at 1.0

@app.route("/get_predictions_with_uncertainty", methods=["POST"])
def get_predictions_with_uncertainty():
    """Get predictions from both models and calculate uncertainty score"""
    data = request.json
    filename = data.get('filename')
    
    if not filename:
        return jsonify({"error": "Filename is required"}), 400
    
    # Check if both models are available and not training
    yolo_status = YOLOModel.get_model_status()
    few_shot_status = FewShotModelTrainer.get_model_status()
    
    print(f"Debug - Model status for uncertainty calculation: YOLO={yolo_status}, FewShot={few_shot_status}")
    
    if yolo_status['training_in_progress'] or few_shot_status['training_in_progress']:
        print(f"Debug - Cannot calculate uncertainty for {filename}, models are still training")
        return jsonify({"error": "Models are still training, please wait"}), 400
    
    if not yolo_status['is_available'] or not few_shot_status['is_available']:
        print(f"Debug - Cannot calculate uncertainty for {filename}, models not available")
        return jsonify({"error": "Both models must be trained before calculating uncertainty"}), 400
        
    # Check if models are ready
    if not yolo_status.get('is_ready', False) or not few_shot_status.get('is_ready', False):
        print(f"Debug - Models are available but not ready yet, forcing ready state")
        
        # Force models ready if they're available but not ready
        if yolo_status['is_available'] and not yolo_status['training_in_progress']:
            with YOLOModel.LOCK:
                YOLOModel.MODEL_READY = True
                print(f"Debug - Forced YOLO model ready state to True")
                
        if few_shot_status['is_available'] and not few_shot_status['training_in_progress']:
            with FewShotModelTrainer.LOCK:
                FewShotModelTrainer.MODEL_READY = True
                print(f"Debug - Forced FewShot model ready state to True")
    
    try:
        # Get predictions from both models
        yolo_predictions = YOLOModel.predict(filename)
        few_shot_predictions = FewShotModelTrainer.predict(filename)
        
        # Convert NumPy types to native Python types and set source to 'ai'
        def convert_numpy_types(obj):
            import numpy as np
            if isinstance(obj, dict):
                # Add source field for prediction dictionaries
                if 'x' in obj and 'y' in obj and 'width' in obj and 'height' in obj:
                    obj['source'] = 'ai'
                    obj['isVerified'] = False
                return {k: convert_numpy_types(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_numpy_types(i) for i in obj]
            elif isinstance(obj, np.integer):
                return int(obj)
            elif isinstance(obj, np.floating):
                return float(obj)
            elif isinstance(obj, np.ndarray):
                return convert_numpy_types(obj.tolist())
            else:
                return obj
        
        # Convert predictions to native Python types
        yolo_predictions = convert_numpy_types(yolo_predictions)
        few_shot_predictions = convert_numpy_types(few_shot_predictions)
        
        # Calculate uncertainty score
        uncertainty_score = calculate_uncertainty_score(yolo_predictions, few_shot_predictions)
        
        # Convert predictions to JSON strings
        yolo_json = json.dumps(yolo_predictions)
        few_shot_json = json.dumps(few_shot_predictions)
        
        # Store uncertainty score and predictions in database
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        c.execute("""
            UPDATE images 
            SET uncertainty_score = ?,
                yolo_predictions = ?,
                one_shot_predictions = ?
            WHERE filename = ?
        """, (float(uncertainty_score), yolo_json, few_shot_json, filename))  # Ensure uncertainty_score is a native Python float
        conn.commit()
        conn.close()
        
        return jsonify({
            "yolo_predictions": yolo_predictions,
            "few_shot_predictions": few_shot_predictions,
            "uncertainty_score": uncertainty_score
        })
    except Exception as e:
        print(f"Error calculating uncertainty: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/reset_annotator", methods=["POST"])
def reset_annotator():
    import shutil
    logger.info("Received request to reset annotator")
    try:
        # Delete all files in uploads directory
        upload_dir = os.path.join(os.getcwd(), 'uploads')
        if os.path.exists(upload_dir):
            for filename in os.listdir(upload_dir):
                file_path = os.path.join(upload_dir, filename)
                try:
                    if os.path.isfile(file_path):
                        os.remove(file_path)
                except Exception as e:
                    logger.error(f"Error deleting file {file_path}: {str(e)}")
        # Delete all files in datasets/train/images and datasets/train/labels
        for subdir in ['datasets/train/images', 'datasets/train/labels']:
            dir_path = os.path.join(os.getcwd(), subdir)
            if os.path.exists(dir_path):
                for filename in os.listdir(dir_path):
                    file_path = os.path.join(dir_path, filename)
                    try:
                        if os.path.isfile(file_path):
                            os.remove(file_path)
                    except Exception as e:
                        logger.error(f"Error deleting file {file_path}: {str(e)}")
        # Remove YOLO model files (runs/detect/train)
        yolo_model_dir = os.path.join(os.getcwd(), 'runs/detect/train')
        if os.path.exists(yolo_model_dir):
            try:
                shutil.rmtree(yolo_model_dir)
                logger.info("Deleted YOLO model directory: runs/detect/train")
            except Exception as e:
                logger.error(f"Error deleting YOLO model directory: {str(e)}")
        # Remove few-shot model files (few_shot_model)
        few_shot_model_dir = os.path.join(os.getcwd(), 'few_shot_model')
        if os.path.exists(few_shot_model_dir):
            try:
                shutil.rmtree(few_shot_model_dir)
                logger.info("Deleted few-shot model directory: few_shot_model")
            except Exception as e:
                logger.error(f"Error deleting few-shot model directory: {str(e)}")
        # Optionally, remove model files (assuming they are in a 'models' directory)
        models_dir = os.path.join(os.getcwd(), 'models')
        if os.path.exists(models_dir):
            try:
                shutil.rmtree(models_dir)
                logger.info("Deleted models directory")
            except Exception as e:
                logger.error(f"Error deleting models directory: {str(e)}")
        # Delete YOLO best model weights
        for yolo_weight in [
            os.path.join('model', 'best.pt'),
            os.path.join('model', 'training', 'weights', 'best.pt')
        ]:
            if os.path.exists(yolo_weight):
                try:
                    os.remove(yolo_weight)
                    logger.info(f"Deleted YOLO weight: {yolo_weight}")
                except Exception as e:
                    logger.error(f"Error deleting YOLO weight {yolo_weight}: {str(e)}")
        # Delete few-shot model weights and classes
        for few_shot_file in [
            os.path.join('model', 'few_shot_model.pt'),
            os.path.join('model', 'few_shot_classes.json')
        ]:
            if os.path.exists(few_shot_file):
                try:
                    os.remove(few_shot_file)
                    logger.info(f"Deleted few-shot file: {few_shot_file}")
                except Exception as e:
                    logger.error(f"Error deleting few-shot file {few_shot_file}: {str(e)}")
        # Clear the images table in the database
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        c.execute("DELETE FROM images")
        conn.commit()
        conn.close()
        # Unload models from memory
        YOLOModel.reset()
        FewShotModelTrainer.reset()
        logger.info("Annotator reset successfully")
        return jsonify({"success": True, "message": "Annotator reset successfully."})
    except Exception as e:
        logger.error(f"Error resetting annotator: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/update_all_uncertainty_scores", methods=["POST"])
def update_all_uncertainty_scores():
    """Update uncertainty scores for all images in the database"""
    try:
        # Check if both models are available and not training
        yolo_status = YOLOModel.get_model_status()
        few_shot_status = FewShotModelTrainer.get_model_status()
        
        print(f"Debug - Model status for updating all uncertainty scores: YOLO={yolo_status}, FewShot={few_shot_status}")
        
        if yolo_status['training_in_progress'] or few_shot_status['training_in_progress']:
            print("Debug - Cannot update uncertainty scores, models are still training")
            return jsonify({"error": "Models are still training, please wait"}), 400
        
        if not yolo_status['is_available'] or not few_shot_status['is_available']:
            print("Debug - Cannot update uncertainty scores, models not available")
            return jsonify({"error": "Both models must be trained before calculating uncertainty"}), 400
        
        # Check if models are ready
        if not yolo_status.get('is_ready', False) or not few_shot_status.get('is_ready', False):
            print("Debug - Models are available but not ready yet, forcing ready state")
            
            # Force models ready if they're available but not ready
            if yolo_status['is_available'] and not yolo_status['training_in_progress'] and not yolo_status.get('is_ready', False):
                with YOLOModel.LOCK:
                    YOLOModel.MODEL_READY = True
                    print("Debug - Forced YOLO model ready state to True")
                    
            if few_shot_status['is_available'] and not few_shot_status['training_in_progress'] and not few_shot_status.get('is_ready', False):
                with FewShotModelTrainer.LOCK:
                    FewShotModelTrainer.MODEL_READY = True
                    print("Debug - Forced FewShot model ready state to True")
        
        # Get all images from database
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        cursor.execute("SELECT filename FROM images WHERE is_fully_annotated = 0")
        rows = cursor.fetchall()
        
        if not rows:
            conn.close()
            return jsonify({"message": "No images found to update"}), 200
        
        updated_count = 0
        
        for row in rows:
            filename = row[0]
            try:
                # Get predictions from both models
                yolo_predictions = YOLOModel.predict(filename)
                few_shot_predictions = FewShotModelTrainer.predict(filename)
                
                # Convert NumPy types to native Python types
                def convert_numpy_types(obj):
                    import numpy as np
                    if isinstance(obj, dict):
                        return {k: convert_numpy_types(v) for k, v in obj.items()}
                    elif isinstance(obj, list):
                        return [convert_numpy_types(i) for i in obj]
                    elif isinstance(obj, np.integer):
                        return int(obj)
                    elif isinstance(obj, np.floating):
                        return float(obj)
                    elif isinstance(obj, np.ndarray):
                        return convert_numpy_types(obj.tolist())
                    else:
                        return obj
                
                yolo_predictions = convert_numpy_types(yolo_predictions)
                few_shot_predictions = convert_numpy_types(few_shot_predictions)
                
                # Calculate uncertainty score
                uncertainty_score = calculate_uncertainty_score(yolo_predictions, few_shot_predictions)
                
                # Convert predictions to JSON strings
                yolo_json = json.dumps(yolo_predictions)
                few_shot_json = json.dumps(few_shot_predictions)
                
                # Update uncertainty score and predictions in database
                cursor.execute('''
                    UPDATE images 
                    SET uncertainty_score = ?,
                        yolo_predictions = ?,
                        one_shot_predictions = ?
                    WHERE filename = ?
                ''', (float(uncertainty_score), yolo_json, few_shot_json, filename))
                conn.commit()
                
                updated_count += 1
                print(f"Debug - Updated uncertainty score and predictions for {filename}: {uncertainty_score}")
                
            except Exception as e:
                print(f"Error updating uncertainty score for {filename}: {str(e)}")
                continue
        
        conn.close()
        return jsonify({"message": f"Updated uncertainty scores for {updated_count} images"}), 200
        
    except Exception as e:
        print(f"Error updating all uncertainty scores: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/auto_training_settings", methods=["GET", "POST"])
def auto_training_settings():
    """Get or update auto-training threshold settings"""
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    
    # Ensure settings table exists
    c.execute('''
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    ''')
    conn.commit()
    
    if request.method == "POST":
        try:
            data = request.json
            threshold = data.get('threshold', 0)
            
            # Save the threshold value
            c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('auto_training_threshold', ?)", 
                     (str(threshold),))
            conn.commit()
            
            return jsonify({"message": "Auto-training threshold saved successfully", "threshold": threshold})
            
        except Exception as e:
            conn.rollback()
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
    else:  # GET
        try:
            # Get the current threshold value
            c.execute("SELECT value FROM settings WHERE key = 'auto_training_threshold'")
            row = c.fetchone()
            
            if row:
                threshold = int(row[0])
            else:
                # Default to 0 (disabled) if not set
                threshold = 0
                c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('auto_training_threshold', '0')")
                conn.commit()
                
            return jsonify({"threshold": threshold})
            
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route("/export_yolo", methods=["GET"])
def export_yolo():
    """
    Export annotations in YOLO format as a ZIP file.
    For images with annotations, use those. For unannotated images, use YOLO predictions.
    """
    try:
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        # Get all images from database
        c.execute("SELECT filename, annotations, yolo_predictions FROM images")
        rows = c.fetchall()
        
        # Create a zip file in memory
        memory_file = io.BytesIO()
        with zipfile.ZipFile(memory_file, 'w') as zf:
            # Create directories in the zip
            zf.writestr('data/images/', '')  # Images directory
            zf.writestr('data/labels/', '')  # Labels directory
            
            # For each image, add the image and its label to the zip
            for row in rows:
                filename = row[0]
                annotations = row[1]  # User annotations
                yolo_predictions = row[2]  # YOLO predictions
                
                # Get the image path
                image_path = os.path.join(UPLOAD_FOLDER, filename)
                
                # Check if image exists
                if not os.path.exists(image_path):
                    print(f"Image not found: {image_path}")
                    continue
                
                # Add image to the zip
                zf.write(image_path, f'data/images/{filename}')
                
                # Convert annotations to YOLO format
                label_content = ""
                
                # Use user annotations if available, otherwise use YOLO predictions
                if annotations and annotations != "null":
                    boxes = json.loads(annotations)
                    label_content = convert_to_yolo_format(boxes, image_path)
                elif yolo_predictions and yolo_predictions != "null":
                    boxes = json.loads(yolo_predictions)
                    label_content = convert_to_yolo_format(boxes, image_path)
                
                # Add label file to the zip
                label_filename = os.path.splitext(filename)[0] + '.txt'
                zf.writestr(f'data/labels/{label_filename}', label_content)
            
            # Add a dataset.yaml file for configuration
            yaml_content = create_dataset_yaml()
            zf.writestr('data/dataset.yaml', yaml_content)
        
        memory_file.seek(0)
        conn.close()
        
        return Response(
            memory_file.getvalue(),
            mimetype='application/zip',
            headers={
                'Content-Disposition': 'attachment; filename=yolo_dataset.zip'
            }
        )
    
    except Exception as e:
        print(f"Error exporting YOLO dataset: {e}")
        return jsonify({"error": str(e)}), 500

def convert_to_yolo_format(boxes, image_path):
    """
    Convert bounding box annotations to YOLO format.
    YOLO format: <class_id> <center_x> <center_y> <width> <height>
    Where all values are normalized to [0, 1]
    """
    try:
        # Get all unique labels across annotations
        all_labels = set()
        for box in boxes:
            if isinstance(box, dict) and 'label' in box:
                all_labels.add(box['label'])
        
        # Create a label map (assign numeric IDs to labels)
        label_map = {label: idx for idx, label in enumerate(sorted(all_labels))}
        
        lines = []
        for box in boxes:
            if not isinstance(box, dict):
                continue
                
            # Extract values (already normalized)
            x = box.get('x', 0.0)
            y = box.get('y', 0.0)
            width = box.get('width', 0.0)
            height = box.get('height', 0.0)
            label = box.get('label', '')
            
            if not label or label not in label_map:
                continue
                
            # Convert to YOLO format (center coordinates)
            center_x = x + (width / 2)
            center_y = y + (height / 2)
            
            # Add to output
            class_id = label_map[label]
            lines.append(f"{class_id} {center_x:.6f} {center_y:.6f} {width:.6f} {height:.6f}")
        
        return "\n".join(lines)
    except Exception as e:
        print(f"Error converting to YOLO format: {e}")
        return ""

def create_dataset_yaml():
    """
    Create a YAML configuration file for the dataset
    """
    # Get all unique labels from the database
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT annotations, yolo_predictions FROM images")
    rows = c.fetchall()
    
    all_labels = set()
    for row in rows:
        annotations = row[0]
        yolo_predictions = row[1]
        
        # Process annotations
        if annotations and annotations != "null":
            try:
                boxes = json.loads(annotations)
                for box in boxes:
                    if isinstance(box, dict) and 'label' in box:
                        all_labels.add(box['label'])
            except:
                pass
                
        # Process YOLO predictions
        if yolo_predictions and yolo_predictions != "null":
            try:
                boxes = json.loads(yolo_predictions)
                for box in boxes:
                    if isinstance(box, dict) and 'label' in box:
                        all_labels.add(box['label'])
            except:
                pass
    
    conn.close()
    
    # Sort labels to ensure consistent class IDs
    sorted_labels = sorted(all_labels)
    
    # Create YAML content
    yaml_content = "# YOLO dataset configuration\n"
    yaml_content += "path: ../data  # Path to dataset\n"
    yaml_content += f"train: images  # Train images\n"
    yaml_content += f"val: images  # Validation images\n\n"
    yaml_content += f"# Classes\n"
    yaml_content += f"names:\n"
    
    for idx, label in enumerate(sorted_labels):
        yaml_content += f"  {idx}: {label}\n"
    
    return yaml_content

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)