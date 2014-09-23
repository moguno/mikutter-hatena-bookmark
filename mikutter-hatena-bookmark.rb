# -*- encoding: utf-8 -*-

require "rubygems"
require "oauth"

Plugin.create :mikutter_hatena_bookmark {
  CONSUMER_KEY = "OGO58BaGZPXV4A=="
  CONSUMER_SECRET = "tsn5V47ZhbVs6GbZ+PWN52QS8g4="

  # コンシューマトークンを得る
  def get_consumer_token
    consumer = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET,
      :site => '',
      :request_token_path => "https://www.hatena.com/oauth/initiate",
      :access_token_path => "https://www.hatena.com/oauth/token",
      :authorize_path  => "https://www.hatena.ne.jp/oauth/authorize")
  end

  # アクセストークンを得る
  def get_access_token(*permissions)
    # OAuthリダイレクト先のWebサーバを起動する
    t = Thread.start {
      s = WEBrick::HTTPServer.new(:Port => 39013)

      key = ""

      s.mount_proc("/") { |req, res|
        if req.query["oauth_verifier"]
          key = req.query["oauth_verifier"].to_s

          res.body = <<EOS
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
</head>
<body>
はてなブックマーク<br>
認証が完了しました。ブラウザを閉じてください。<br>
</body>
</html>
EOS
          s.stop
        end
      }

      s.start

      key
    }

    # 認証開始
    consumer = get_consumer_token

    request = consumer.get_request_token({:oauth_callback => "http://127.0.0.1:39013"}, :scope => permissions.join(","))
    Gtk::openurl(request.authorize_url)

    # コールバック先がアクセストークンを得るまで待つ
    if !t.join(60 * 2)
      return nil
    end

    access = request.get_access_token({}, :oauth_verifier => t.value)

    { :token => access.token, :secret => access.secret }
  end

  # 設定ウインドウ
  settings("はてなブックマーク") {
    closeup decide = ::Gtk::Button.new('アカウント認証')
    decide.signal_connect("clicked") {
      token = Plugin[:mikutter_hatena_bookmark].get_access_token("read_public", "write_public")

      if token
        UserConfig[:hatena_bookmark_access_token] = token
      end
    }
  }

  # ツイート中のURLをはてなブックマークに送信するコマンド
  command(:send_to_hatena_bookmark,
          :name => _("URLをはてなブックマークに送信"),
          :condition => lambda { |opt| (opt.messages.length > 0) && UserConfig[:hatena_bookmark_access_token] },
          :visible => true,
          :icon => "http://b.hatena.ne.jp/favicon.ico",
          :role => :timeline) { |opt|
    begin
      access_token = UserConfig[:hatena_bookmark_access_token]

      access = OAuth::AccessToken.new(get_consumer_token, access_token[:token], access_token[:secret])

      opt.messages.each { |msg|
        msg[:entities][:urls].each { |url|
          params = {
            :url => url[:expanded_url],
            :comment => msg[:message],
            :tags => "from mikutter",
          }

          # 送信
          response = access.request(:post, "http://api.b.hatena.ne.jp/1/my/bookmark", params, "")
        }
      }
    rescue => e
      puts e
      puts e.backtrace
    end
  }
}
