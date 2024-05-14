# Pull nodejs image
FROM --platform=linux/amd64 node:18-alpine
# FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Expose port
EXPOSE 3000

# Start server
CMD ["node", "index.js"]
