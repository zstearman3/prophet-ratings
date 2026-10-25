ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY app/javascript ./app/javascript
RUN yarn build && cp -r app/assets/builds /compiled
