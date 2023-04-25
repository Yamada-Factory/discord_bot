FROM ruby:2.7.3-alpine3.13

RUN apk update
RUN apk add --update --no-cache g++ make openssl imagemagick imagemagick-dev imagemagick-libs
RUN gem update --system
RUN gem install discordrb dotenv rmagick
COPY bot.rb bot.rb
COPY .env .env
CMD ["ruby", "bot.rb"]
