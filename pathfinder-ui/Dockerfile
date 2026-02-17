# Angular UI Dockerfile
# Multi-stage build with nginx for production

# Stage 1: Build
FROM node:18-alpine AS build
WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci --legacy-peer-deps

# Copy source code and build for production
COPY . .
RUN npm run build -- --configuration production

# Stage 2: Serve with nginx
FROM nginx:alpine AS runtime

# Copy built app to nginx html directory
COPY --from=build /app/dist/pathfinder-ui/browser /usr/share/nginx/html

# Copy custom nginx configuration
# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# Start nginx with envsubst
CMD ["/bin/sh", "-c", "envsubst < /usr/share/nginx/html/assets/env.template.js > /usr/share/nginx/html/assets/env.js && exec nginx -g 'daemon off;'"]
