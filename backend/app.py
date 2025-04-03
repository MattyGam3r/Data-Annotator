import os
import sqlite3
from flask import Flask, jsonify, Response, request, render_template, send_from_directory
from flask_cors import CORS, cross_origin
from werkzeug import utils


app = Flask(__name__)
cors = CORS(app, 
            origins=["http://localhost:8080", "localhost:8080"],
            methods=["POST", "OPTIONS"],
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
              UNIQUE (filename)
            );
    ''')
    conn.commit()
    conn.close()

init_db()

@app.route("/")
def home():
    return jsonify({"message": "Hello from Flask!"})




@app.route("/upload", methods = ["POST"])
def upload_image():
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        imagefiles = request.files.getlist('image')
        #TODO: Get secure filename eventually
        #filename = werkzeug.utils.secure_filename(imagefile.filename)
        for file in imagefiles:
            file.save("./uploads/" + file.filename)
        #Insert the image into the database
            c.execute("INSERT INTO images (filename) VALUES (?)", (file.filename,))
        conn.commit()
        conn.close()
        response = jsonify({
            "message": "Image(s) Uploaded Successfully"
        })
        return response

#This function returns all images to the user
@app.route("/images", methods = ["GET"])
def get_images():
     conn = sqlite3.connect(DATABASE)
     c = conn.cursor()
     c.execute("SELECT filename FROM images")
     rows = c.fetchall()
     data = [{"filename": row[0]} for row in rows]
     return jsonify(data)

@app.route("/uploads/<filename>", methods = ['GET'])
def get_image(filename):
     return send_from_directory("./uploads/", filename)

     


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)