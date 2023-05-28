# frozen_string_literal: true

require 'discordrb'
require 'dotenv'
require 'net/http'
require 'uri'
require 'json'
require 'rmagick'

# load .env
Dotenv.load

# カラーコードの画像生成
def create_color_image(color_code, width = 25, height = 25)
  image = Magick::Image.new(width, height) do |img|
    img.background_color = Magick::Pixel.from_color(color_code)
  end

  filename = "./tmp/#{color_code}.png"

  image.write(filename)

  return filename
end

# 入力のmessageに対し、referenced_message がnilを返すまで再帰的に呼び出す
def get_referenced_message(message, replies = [])
  replies.unshift(message)
  return replies if message.referenced_message.nil?

  get_referenced_message(message.referenced_message, replies)
end

# 返信一覧を取得して送信するmessageを組み立てる
def get_body_messages(message, bot)
  replies = get_referenced_message(message)

  body = []
  replies.each do |reply|
    role = reply.from_bot? && reply.author.username == bot.profile.name ? 'assistant' : 'user'
    body.push({
      'role': role,
      'content': reply.content.gsub('/gpt ', ''),
    })
  end

  return body
end

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
openai_key_dalle = ENV['OPENAI_API_KEY_DALLE']
max_replay_length = ENV['MAX_REPLAY_LENGTH'].to_i

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
  # 入力中イベントを送信
  event.channel.start_typing()

  url = URI("https://api.openai.com/v1/chat/completions")

  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true
  https.read_timeout = 120

  request = Net::HTTP::Post.new(url)
  request["Content-Type"] = "application/json"
  request["Authorization"] = "Bearer #{openai_key}"

  body_messages = get_body_messages(event.message, bot)

  if body_messages.length > max_replay_length
    event.message.reply!("🙇 #{max_replay_length}回以上の会話はできません!!")
    return
  end

  body = {
    "model": "gpt-3.5-turbo",
    "messages": body_messages,
    "temperature": 0.7
  }
  request.body = JSON.dump(body)

  begin
    response = https.request(request)
    if response.code != '200'
      event.respond('エラーが発生しました' + response.read_body)
      return
    end

    data = JSON.parse(response.read_body)

    # discordの投稿に返信する
    event.message.reply!(data['choices'][0]['message']['content'])
  rescue Net::ReadTimeout => e
    event.message.reply!('タイムアウトエラーが発生しました')
  end

  return
end

# DalleのAPIを叩いて画像を生成する
bot.command :dalle do |event, *args|
  # 入力中イベントを送信
  event.channel.start_typing()

  url = URI("https://api.openai.com/v1/images/generations")

  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true

  request = Net::HTTP::Post.new(url)
  request["Content-Type"] = "application/json"
  request["Authorization"] = "Bearer #{openai_key_dalle}"
  body = {
    'prompt': args.join(' '),
    'n': 1,
    'size': '256x256',
  }
  request.body = JSON.dump(body)

  response = https.request(request)
  if response.code != '200'
    event.respond('エラーが発生しました' + response.read_body)
    return
  end

  data = JSON.parse(response.read_body)

  # discordの投稿に返信する
  for d in data['data'] do
    event.respond(d['url'])
  end

  return
end

bot.message do |event|
  # メッセージ内のカラーコードを検出
  color_codes = event.content.scan(/(?<!<)#(?:[0-9a-fA-F]{3}){1,2}(?!>)/)

  # カラーコードが見つかった場合、画像を生成して送信
  color_codes.each do |color_code|
    image_filename = create_color_image(color_code)
    event.send_file(File.open(image_filename, 'r'), caption: color_code)

    # 一時ファイルを削除
    File.delete(image_filename)
  end
end

bot.run
