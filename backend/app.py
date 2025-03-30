import os
import sqlite3
from flask import Flask, jsonify, Response, request
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
              upload_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
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
        imagefiles = request.files.getlist('image')
        #TODO: Get secure filename eventually
        #filename = werkzeug.utils.secure_filename(imagefile.filename)
        for file in imagefiles:
            file.save("./uploads/" + file.filename)
        #Insert the image into the database
        conn = sqlite3.connect(DATABASE)
        c = conn.cursor()
        c.execute("INSERT INTO images (filename) VALUES (?)", (file.filename,))
        conn.commit()
        conn.close()
        response = jsonify({
            "message": "Image(s) Uploaded Successfully"
        })
        return response



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)