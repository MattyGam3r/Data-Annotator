import os
import sqlite3
import json
from flask import Flask, jsonify, Response, request, render_template, send_from_directory
from flask_cors import CORS, cross_origin
from werkzeug import utils
from yolo_model import YOLOModel

app = Flask(__name__)
cors = CORS(app, 
            origins=["http://localhost:8080", "localhost:8080"],
            methods=["POST", "OPTIONS", "GET"],
            allow_headers=["Content-Type"])

#Store Uploads Here:
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

#Sqlite database to hold the images
DATABASE = 'metadata.db'


def init_db():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            upload_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            annotations TEXT,
            is_fully_annotated BOOLEAN DEFAULT 0,
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
    c.execute("SELECT filename, upload_time, annotations, is_fully_annotated FROM images")
    rows = c.fetchall()
    data = [{
        "filename": row[0], 
        "upload_time": row[1], 
        "annotations": row[2],
        "isFullyAnnotated": bool(row[3])
    } for row in rows]
    return jsonify(data)

@cross_origin
@app.route("/uploads/<filename>", methods=['GET'])
def get_image(filename):
    return send_from_directory("./uploads/", filename)

@app.route("/save_annotations", methods=["POST"])
def save_annotations():
    data = request.json
    filename = data.get('filename')
    annotations = data.get('annotations')
    is_fully_annotated = data.get('isFullyAnnotated', False)
    
    if not filename or filename.strip() == '':
        return jsonify({"error": "Filename is required"}), 400
    
    # Extract just the filename part (remove any URL components)
    filename = filename.split('/')[-1]
    
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    
    try:
        c.execute("UPDATE images SET annotations = ?, is_fully_annotated = ? WHERE filename = ?", 
                 (annotations, is_fully_annotated, filename))
        conn.commit()
        
        if c.rowcount == 0:
            return jsonify({"error": "Image not found"}), 404
            
        return jsonify({"message": "Annotations saved successfully"})
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route("/model_status", methods=["GET"])
def get_model_status():
    """Get the current status of the YOLO model"""
    return jsonify(YOLOModel.get_model_status())

@app.route("/train_model", methods=["POST"])
def train_model():
    """Start training the YOLO model with annotated data"""
    data = request.json
    images = data.get('images', [])
    
    success = YOLOModel.start_training(images)
    
    if success:
        return jsonify({"message": "Model training started"})
    else:
        return jsonify({"error": "Training already in progress"}), 400

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
        
        # Get class names from original annotations
        class_names = {}
        if original_annotations:
            try:
                original_boxes = json.loads(original_annotations)
                for i, box in enumerate(original_boxes):
                    class_names[i] = box.get('label', f'class_{i}')
                print(f"Class names mapping: {class_names}")
            except Exception as e:
                print(f"Error parsing original annotations: {str(e)}")
        
        augmented_images.append({
            'url': f'/uploads/{filename}',
            'is_original': True,
            'annotations': original_annotations
        })
        
        # Look for augmented versions in the training dataset
        train_dir = 'datasets/train/images'
        labels_dir = 'datasets/train/labels'
        print(f"Checking directories: {train_dir} and {labels_dir}")
        print(f"Train dir exists: {os.path.exists(train_dir)}")
        print(f"Labels dir exists: {os.path.exists(labels_dir)}")
        
        if os.path.exists(train_dir) and os.path.exists(labels_dir):
            base_name = os.path.splitext(filename)[0]
            print(f"Looking for augmented files starting with {base_name}_aug")
            
            for aug_file in os.listdir(train_dir):
                print(f"Checking file: {aug_file}")
                if aug_file.startswith(f"{base_name}_aug") and aug_file.endswith(os.path.splitext(filename)[1]):
                    print(f"Found matching augmented file: {aug_file}")
                    
                    # Always copy the augmented image to uploads to ensure we have the latest version
                    src_path = os.path.join(train_dir, aug_file)
                    dst_path = os.path.join('uploads', aug_file)
                    print(f"Copying {aug_file} to uploads directory")
                    import shutil
                    shutil.copy2(src_path, dst_path)
                    
                    # Get annotations for the augmented image
                    # For augmented images, the label file should be like 'dog_aug0.txt'
                    aug_label_file = os.path.join(labels_dir, os.path.splitext(aug_file)[0] + '.txt')
                    print(f"Looking for label file: {aug_label_file}")
                    annotations = None
                    
                    # Try both the exact filename and the base name
                    possible_label_files = [
                        aug_label_file,  # Try with augmented filename (e.g., dog_aug0.txt)
                        os.path.join(labels_dir, os.path.splitext(filename)[0] + '.txt')  # Try with original filename (e.g., dog.txt)
                    ]
                    
                    print(f"Trying possible label files: {possible_label_files}")
                    
                    for label_file in possible_label_files:
                        print(f"Trying label file: {label_file}")
                        if os.path.exists(label_file):
                            print(f"Found label file: {label_file}")
                            boxes = []
                            with open(label_file, 'r') as f:
                                content = f.read()
                                print(f"Raw label file content:\n{content}")
                                f.seek(0)  # Reset file pointer to beginning
                                for line_num, line in enumerate(f, 1):
                                    try:
                                        parts = line.strip().split()
                                        print(f"Line {line_num} - Raw parts: {parts}")
                                        if len(parts) >= 5:
                                            # Convert class_id from float to int
                                            class_id = int(float(parts[0]))
                                            x_center = float(parts[1])
                                            y_center = float(parts[2])
                                            width = float(parts[3])
                                            height = float(parts[4])
                                            
                                            print(f"Line {line_num} - Parsed values:")
                                            print(f"  class_id: {class_id}")
                                            print(f"  x_center: {x_center}")
                                            print(f"  y_center: {y_center}")
                                            print(f"  width: {width}")
                                            print(f"  height: {height}")
                                            
                                            # Convert from YOLO format (center x, center y, width, height)
                                            # to our format (top-left x, top-left y, width, height)
                                            x = x_center - width/2
                                            y = y_center - height/2
                                            
                                            print(f"Line {line_num} - Converted coordinates:")
                                            print(f"  x: {x}")
                                            print(f"  y: {y}")
                                            print(f"  width: {width}")
                                            print(f"  height: {height}")
                                            
                                            # Get class name from our mapping
                                            label = class_names.get(class_id, f'class_{class_id}')
                                            print(f"Line {line_num} - Using label: {label}")
                                            
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
                                            print(f"Line {line_num} - Created box: {box}")
                                            boxes.append(box)
                                    except Exception as e:
                                        print(f"Error parsing line {line_num}: {line}")
                                        print(f"Error details: {str(e)}")
                                        continue
                            if boxes:
                                annotations = json.dumps(boxes)
                                print(f"Final annotations JSON: {annotations}")
                                break  # Stop looking if we found valid annotations
                            else:
                                print("No valid boxes were created from the label file")
                    
                    augmented_images.append({
                        'url': f'/uploads/{aug_file}',
                        'is_original': False,
                        'annotations': annotations
                    })
        
        if conn:
            conn.close()
        print(f"Returning {len(augmented_images)} images")
        return jsonify({"images": augmented_images})
    except Exception as e:
        if conn:
            conn.close()
        print(f"Error in get_augmented_images: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/predict", methods=["POST"])
def predict():
    """Get predictions for an image"""
    data = request.json
    filename = data.get('filename')
    
    if not filename:
        return jsonify({"error": "Filename is required"}), 400
    
    predictions = YOLOModel.predict(filename)
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
    return jsonify({"predictions": predictions})

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
        c.execute("UPDATE images SET is_fully_annotated = 1 WHERE filename = ?", (filename,))
        conn.commit()
        
        if c.rowcount == 0:
            return jsonify({"error": "Image not found"}), 404
            
        return jsonify({"message": "Image marked as fully annotated"})
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)