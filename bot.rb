# frozen_string_literal: true

require 'discordrb'
require 'dotenv'
require 'net/http'
require 'uri'
require 'json'

# load .env
Dotenv.load

class UserState
    # 初期化
    def initialize
        @user_state = { 'no_user' => { 'voiceChannel' => nil, 'isMute' => false}}
    end

    def getUserState(user_name)
        return @user_state[user_name]
    end

    def setUserState(user_name, voiceChannel, isMute)
        @user_state[user_name] = {} unless @user_state.key?(user_name)
        @user_state[user_name]['voiceChannel'] = voiceChannel
        @user_state[user_name]['isMute'] = isMute
    end
end

user_state = UserState.new

# envより設定
token = ENV['TOKEN_KEY']
client_id = ENV['CLIENT_ID']
inform_channel = ENV['INFORM_CHANNEL_ID']
bot_user_name = ENV['BOT_NAME']
github_token = ENV['GITHUB_TOKEN']
openai_key = ENV['OPENAI_API_KEY']

bot = Discordrb::Commands::CommandBot.new token: token, client_id: client_id, prefix: '/'

# 誰かがvoice channnelに出入りしたら発火
bot.voice_state_update do |event|
    user_name = event.user.name.to_s

    next if user_name == bot_user_name

    isMute = event.self_mute
    beforeState = user_state.getUserState(user_name).clone

    # 登録がなくて，初めての通知の時エントリーを登録
    if beforeState.nil?
        user_state.setUserState(user_name, false, isMute)
    end

    channel = event.channel
    # チャンネルデータがないときは出ていったとき
    if channel.nil?
        channel_name = event.old_channel.name
        bot.send_message(inform_channel, "#{user_name} が #{channel_name}を出たで～")
        user_state.setUserState(user_name, nil, isMute)
    else
        channel_name = event.channel.name
        user_state.setUserState(user_name, channel_name, isMute)

        # voiceChannelが現在のチャネルのときはすでにボイスチャネルに入ってるので通知しない
        next if !beforeState.nil? && beforeState['voiceChannel'] == channel_name

        # それ以外の時は通知する
        bot.send_message(inform_channel, "#{user_name} が #{channel_name}に入ったで～")
    end
end

# /deploy <branch>で起動
bot.command :deploy do |event, branch|
  # developチャンネル以外は弾く
  break if event.channel.name != 'nitncwind-develop'

  uri = URI.parse('https://api.github.com/repos/nitncwind-org/v3/actions/workflows/1977992/dispatches')
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "token #{github_token}"
  request['Accept'] = 'application/vnd.github.v3:json'
  request.body = JSON.dump(
    'ref' => branch
  )

  req_options = {
    use_ssl: uri.scheme == 'https'
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end

  puts response.code

  # レスポンスが204ならデプロイ通知
  if response.code == '204'
    bot.send_message('738448323773595650', "devに `#{branch}`  をデプロイすんで")
  end
end

# /gptコマンドで文字列を受け取り、GPTのAPIを叩いて返す
bot.command :gpt do |event, *args|
  url = URI("https://api.openai.com/v1/chat/completions")

  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true

  request = Net::HTTP::Post.new(url)
  request["Content-Type"] = "application/json"
  request["Authorization"] = "Bearer #{openai_key}"
  body = {
    "model": "gpt-3.5-turbo",
    "messages": [
      {
        "role": "user",
        "content": args.join(' ')
      }
    ],
    "temperature": 0.7
  }
  request.body = JSON.dump(body)

  response = https.request(request)
  if response.code != '200'
    event.respond('エラーが発生しました' + response.read_body)
    return
  end

  data = JSON.parse(response.read_body)

  # discordの投稿に返信する
  event.respond(data['choices'][0]['message']['content'])
end

bot.run
