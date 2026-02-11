#!/bin/bash
# Script to build translated documentation for Zuul
# This script should be run from the doc directory
# Usage: ./build-translated-lang.sh <language_code>
# Example: ./build-translated-lang.sh ko_KR

set -e  # Exit on error

# Check for language parameter
if [ -z "$1" ]; then
    echo "Error: Language code is required"
    echo "Usage: ./build-translated-lang.sh <language_code>"
    echo "Example: ./build-translated-lang.sh ja"
    echo "         ./build-translated-lang.sh ko_KR"
    echo "         ./build-translated-lang.sh en_GB"
    exit 1
fi

LANG_CODE="$1"

echo "=========================================="
echo "Zuul Translated Documentation Build Script"
echo "Language: $LANG_CODE"
echo "=========================================="
echo ""

# Check if we're in the doc directory
if [ ! -f "source/conf.py" ]; then
    echo "Error: This script must be run from the doc directory"
    echo "Usage: cd doc && ./build-translated-lang.sh <language_code>"
    exit 1
fi

# Step 1: Create virtual environment if it doesn't exist
echo "[1/7] Checking virtual environment..."
if [ ! -d "../venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv ../venv
    echo "Virtual environment created."
else
    echo "Virtual environment already exists."
fi

# Step 2: Activate virtual environment and install dependencies
echo ""
echo "[2/7] Installing dependencies..."
source ../venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install 'setuptools<82' > /dev/null 2>&1
pip install -r ../requirements.txt
pip install -r ../test-requirements.txt
pip install -r requirements.txt
pip install -e ..
echo "Dependencies installed."

# # Step 3: Generate pot files
# echo ""
# echo "[3/7] Generating pot files..."
# make gettext > /dev/null 2>&1
# echo "Pot files generated in build/locale/"

# # Step 4: Initialize po files if they don't exist
# echo ""
# echo "[4/7] Checking $LANG_CODE po files..."
# if [ ! -d "source/locale/$LANG_CODE/LC_MESSAGES" ]; then
#     echo "Creating $LANG_CODE po files from pot files..."
#     mkdir -p "source/locale/$LANG_CODE/LC_MESSAGES"
#     for potfile in build/locale/*.pot; do
#         filename=$(basename "$potfile" .pot)
#         msginit --input="$potfile" --locale="$LANG_CODE" --output="source/locale/$LANG_CODE/LC_MESSAGES/${filename}.po" --no-translator
#     done
#     echo "$LANG_CODE po files created. Please translate msgstr entries manually."
# else
#     echo "$LANG_CODE po files already exist in source/locale/$LANG_CODE/LC_MESSAGES/"
# fi

# Step 5: Compile po files to mo files
echo ""
echo "[5/7] Compiling po files to mo files..."
for pofile in source/locale/$LANG_CODE/LC_MESSAGES/*.po; do
    mofile="${pofile%.po}.mo"
    msgfmt "$pofile" -o "$mofile"
done
echo "All po files compiled to mo files."

# Step 6: Update conf.py if locale_dirs is not configured
echo ""
echo "[6/7] Checking conf.py configuration..."
if ! grep -q "locale_dirs" source/conf.py; then
    echo "Adding locale_dirs configuration to conf.py..."
    # Find the line with "primary_domain = 'zuul'" and add locale config before it
    sed -i "/^primary_domain = 'zuul'/i\\# Internationalization\\nlocale_dirs = ['locale/']\\ngettext_compact = False\\n" source/conf.py
    echo "locale_dirs configuration added to conf.py."
else
    echo "locale_dirs already configured in conf.py."
fi

# Step 7: Build translated HTML documentation
echo ""
echo "[7/7] Building $LANG_CODE HTML documentation..."
rm -rf "build/html/$LANG_CODE"
sphinx-build -a -b html -D language="$LANG_CODE" source "build/html/$LANG_CODE"
echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "$LANG_CODE documentation is available at: build/html/$LANG_CODE/index.html"
echo ""
echo "To view the documentation, open build/html/$LANG_CODE/index.html in a web browser."
echo ""
