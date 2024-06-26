FROM ruby:3.2-alpine3.18

RUN apk update
RUN apk add --update --no-cache g++ make openssl imagemagick imagemagick-dev imagemagick-libs libsodium
RUN gem update --system
RUN gem install discordrb dotenv rmagick
COPY bot.rb bot.rb
COPY .env .env
CMD ["ruby", "bot.rb"]
