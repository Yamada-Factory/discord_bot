FROM ruby:2.7.3-alpine3.13

RUN apk update
RUN apk add --no-cache g++ make openssl
RUN gem update --system
RUN gem install discordrb dotenv chunky_png
COPY bot.rb bot.rb
COPY .env .env
CMD ["ruby", "bot.rb"]
