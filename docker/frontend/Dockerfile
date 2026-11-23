FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG API_URL
RUN grep -rlE "^[[:space:]]*const url[[:space:]]*=" src \
    | xargs -r sed -i -E "s|const url[[:space:]]*=.*|const url = \"${API_URL}\";|" \
 ; grep -rn "localhost:4000" src || true
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
