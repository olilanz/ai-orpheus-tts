#!/bin/bash

set -euo pipefail  # Exit on error, show commands, handle pipes safely

echo "🔧 Running startup script..."

if [[ -z "${HF_TOKEN}" ]]; then
    echo "Error: HF_TOKEN is not set or is empty. Please specify your Huggingface access token, as some models require authentication."
    exit 1
fi

# Set up environment variables
AUTO_UPDATE=${AUTO_UPDATE:-0}

CACHE_HOME="/workspace/cache"
export HF_HOME="${CACHE_HOME}/huggingface"
export TORCH_HOME="${CACHE_HOME}/torch"
OUTPUT_HOME="/workspace/output"

echo "📂 Setting up cache directories..."
mkdir -p "${CACHE_HOME}" "${HF_HOME}"  "${TORCH_HOME}" "${OUTPUT_HOME}"

# Virtual environment setup
VENV_HOME="${CACHE_HOME}/venv"
echo "📦 Setting up Python virtual environment..."
if [ ! -d "$VENV_HOME" ]; then
    # Create virtual environment, but re-use globally installed packages if available (e.g. via base container)
    python3 -m venv "$VENV_HOME" --system-site-packages
fi
source "${VENV_HOME}/bin/activate"

# Ensure latest pip version
pip install --no-cache-dir --upgrade pip wheel

# Clone or update application repository
NEEDS_INSTALL=0
REPO_HOME="${CACHE_HOME}/repo"
if [ ! -d "$REPO_HOME" ]; then
    echo "📥 Unpacking app repository..."
    mkdir -p "$REPO_HOME"
    tar -xzvf APP.tar.gz --strip-components=1 -C "$REPO_HOME"
    NEEDS_INSTALL=1
fi

if [[ "$AUTO_UPDATE" == "1" ]]; then
    echo "🔄 Updating the MMAudio repository..."
    git -C "$REPO_HOME" reset --hard
    git -C "$REPO_HOME" pull
    NEEDS_INSTALL=1
fi

# patching the start-up function, so that the script listens on the public network interface
if grep -q 'demo.queue(max_size=20).launch(share=True, server_name="0.0.0.0", server_port=7860)' "$REPO_HOME/app.py"; then
    echo "Launch function is already patched."
else
    # Replace demo.launch() with demo.launch(server_name="0.0.0.0", server_port=args.port)
    # This causes the Gradio server to listen on all network interfaces
    sed -i 's/demo.queue(max_size=20).launch(share=True)/demo.queue(max_size=20).launch(share=True, server_name="0.0.0.0", server_port=7860)/g' "$REPO_HOME/app.py"
    echo "Launch function patched with demo.queue(max_size=20).launch(share=True, server_name="0.0.0.0", server_port=7860)."
    NEEDS_INSTALL=1
fi

if [[ "$NEEDS_INSTALL" == "1" ]]; then
    echo "📦 Installing Python dependencies..."
    pip install -r "$REPO_HOME/requirements.txt"
fi

# Start the service
echo "🚀 Starting the application..."
cd "$REPO_HOME"
python3 -u app.py 2>&1 | tee "${CACHE_HOME}/output.log"
echo "❌ The application has terminated."
