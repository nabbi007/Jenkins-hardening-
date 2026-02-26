FROM node:20-alpine AS build

WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY src ./src
RUN npm run build

FROM nginx:1.27-alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Fix permissions for the built-in nginx user (already exists in the base image).
RUN chown -R nginx:nginx /var/cache/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid && \
    chown -R nginx:nginx /usr/share/nginx/html

USER nginx

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1/nginx-health || exit 1

CMD ["nginx", "-g", "daemon off;"]
