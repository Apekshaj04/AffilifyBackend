FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN npm i -g nodemon

ENV NODE_ENV=development
EXPOSE 3000
    
CMD ["nodemon", "--legacy-watch", "index.js"]
