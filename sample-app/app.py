from flask import Flask, jsonify, request
import os
import socket
import datetime

app = Flask(__name__)

@app.route('/')
def home():
    hostname = socket.gethostname()
    return jsonify({
        'message': 'Welcome to Kubernetes Sample App!',
        'hostname': hostname,
        'timestamp': datetime.datetime.now().isoformat(),
        'version': '1.0.0'
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/ready')
def ready():
    return jsonify({'status': 'ready'}), 200

@app.route('/info')
def info():
    return jsonify({
        'hostname': socket.gethostname(),
        'environment': os.environ.get('ENVIRONMENT', 'production'),
        'python_version': os.sys.version,
        'app_name': 'kubernetes-sample-app'
    })

@app.route('/api/data', methods=['GET', 'POST'])
def data():
    if request.method == 'POST':
        data = request.get_json()
        return jsonify({
            'message': 'Data received',
            'data': data,
            'timestamp': datetime.datetime.now().isoformat()
        }), 201
    else:
        return jsonify({
            'message': 'Use POST method to submit data',
            'example': {
                'name': 'example',
                'value': 'test'
            }
        })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
