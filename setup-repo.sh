#!/bin/bash

# Initialize git repository
git init

# Add all files
git add .

# Commit the files
git commit -m "Initial commit with multi-project structure"

# Instructions for connecting to GitHub
echo "
Repository initialized locally. To push to GitHub:

1. Create a new repository on GitHub (https://github.com/new)
2. Run the following commands:

git remote add origin https://github.com/drascom/projects.git
git branch -M main
git push -u origin main
"