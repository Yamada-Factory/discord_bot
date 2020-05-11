# frozen_string_literal: true

require 'discordrb'
require 'dotenv'

# load .env
Dotenv.load

# ユーザのセッションを管理する
class User
  # 初期化
  def initialize
    @user_status = { 'no_user' => { 'status' => 'offline', 'mute' => 'false' } }
  end

  # userの状態を返す
  def getUserStatus(user_name)
    return @user_status[user_name] if @user_status.key?(user_name)

    { 'status' => 'offline' }
  end

  # userの状態を更新
  def setUserStatus(user_name, status, mute)
    @user_status[user_name] = {} unless @user_status.key?(user_name)
    @user_status[user_name]['status'] = status
    @user_status[user_name]['mute'] = mute.to_s
    # offlineの時は削除
    @user_status.delete(user_name) if status == 'offline'
  end
end

# controller
user_session = User.new

# envより設定
token = ENV['TOKEN_KEY']
client_id = ENV['CLIENT_ID']
inform_channel = ENV['INFORM_CHANNEL_ID']
bot_user_name = ENV['BOT_NAME']

bot = Discordrb::Commands::CommandBot.new token: token, client_id: client_id, prefix: '/'

# 誰かがvoice channnelに出入りしたら発火
bot.voice_state_update do |event|
  # イベントが発火したボイスチャンネルデータを取得
  channel = event.channel

  # 発火させたユーザー名を取得
  user = event.user.name.to_s

  # botは削除
  break if user == bot_user_name

  # ミュートの状態を取得
  mute_status = event.self_mute.to_s
  # 元のミュート状態を取得
  before_mute = user_session.getUserStatus(user)['mute'].to_s
  # 現状態を上書き
  user_session.setUserStatus(user, 'online', mute_status)
  # 元の状態が遷移した時は無視
  break if before_mute != mute_status

  # もしデータが空だと抜けていったチャンネルを取得
  if channel.nil?
    # チャンネル名を取得
    channel_name = event.old_channel.name
    # 退出したことをinform_channelに通知
    bot.send_message(inform_channel, "@everyone #{user} が #{channel_name}を出たで～")
  else
    # チャンネル名を取得
    channel_name = event.channel.name
    # 入室したことをinform_channelに通知
    bot.send_message(inform_channel, "@everyone #{user} が #{channel_name}に入ったで～")
  end
end

# 誰かの状態が変われば発火
bot.presence do |event|
  # ユーザー名の取得
  user = event.user.name.to_s
  # 遷移した状態の取得
  state = event.status.to_s
  # 元の状態を取得
  before_status = user_session.getUserStatus(user)['status'].to_s
  # 状態を更新
  user_session.setUserStatus(user, state, false)
  p "#{user} is #{before_status} => #{state}"
  # 元の状態がofflineの時通知
  if before_status == 'offline' || state == 'offline'
    # 通知センターに投下
    bot.send_message(inform_channel, "#{user} is **#{state}**")
  end
end

bot.run
