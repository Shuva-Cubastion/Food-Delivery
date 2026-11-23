FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
RUN grep -rl "const frontend_url" --include=*.js . --exclude-dir=node_modules \
    | xargs -r sed -i -E 's|const frontend_url[[:space:]]*=.*|const frontend_url = process.env.FRONTEND_URL;|' \
 && mkdir -p uploads && chown -R node:node /app
USER node
EXPOSE 4000
CMD ["node", "server.js"]
