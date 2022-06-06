FROM ruby:2.7.3-alpine3.13

RUN apk update --system
RUN apk add --no-cache g++ make openssl
RUN gem install discordrb dotenv
COPY bot.rb bot.rb
CMD ["ruby", "bot.rb"]
