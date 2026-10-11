# ==========================================
# Dockerfile for Backend Web API
# ==========================================
FROM node:18-alpine

WORKDIR /app

# Copy dependency files first for layer caching
COPY package*.json ./

# Install dependencies (including pg and express)
RUN npm install --omit=dev

# Copy application source code
COPY . .

# Expose backend service port
EXPOSE 3000

# Start Backend API
CMD ["node", "server.js"]
