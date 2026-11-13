module Invidious::Routes::Companion
  extend self

  # GET /companion
  def get_companion(env)
    url = make_url(env)
    proxy_companion(env, "GET", url)
  end

  # POST /companion
  def post_companion(env)
    url = make_url(env)
    proxy_companion(env, "POST", url)
  end

  # OPTIONS /companion
  def options_companion(env)
    url = make_url(env)
    proxy_companion(env, "OPTIONS", url)
  end

  private def make_url(env)
    url = env.request.path
    if env.request.query
      url += "?#{env.request.query}"
    end
    url
  end

  private def proxy_companion(env, method, url)
    if method == "GET" && env.request.path == "/companion/videoplayback"
      return if stream_videoplayback_direct(env)
    end
    begin
      COMPANION_POOL.client do |wrapper|
        wrapper.client.exec(method, url, env.request.headers, (env.request.body if method == "POST")) do |resp|
          env.response.status_code = resp.status_code
          resp.headers.each do |key, value|
            env.response.headers[key] = value
          end
          return IO.copy resp.body_io, env.response
        end
      end
    rescue
      env.response.headers.clear
      return Errors.error_json(502, "Couldn't proxy request to Invidious Companion.")
    end
  end

  # Stream media bytes straight from googlevideo instead of relaying them
  # through the companion. The videoplayback URLs the companion generates are
  # fully signed (signature and PO token are part of the query string), so
  # fetching them ourselves is equivalent. This works around the companion
  # intermittently (10-15% of requests, only for some CDN edges, surviving
  # restarts) answering with a synthesized 206 header and zero body bytes,
  # which stalls the player and freezes videos mid-playback (same failure
  # family as iv-org/invidious#5779).
  #
  # googlevideo sometimes bounces a videoplayback URL between CDN edges
  # (cms_redirect) before serving it. Those redirects must be followed here,
  # server-side, and never passed through to the client: the signed URLs are
  # for non-web clients (no Access-Control-Allow-Origin on the responses), so
  # a browser that follows the redirect cross-origin fails CORS in the DASH
  # player and the video never starts.
  #
  # Returns true when the request was handled; false when the caller should
  # fall back to relaying through the companion.
  private def stream_videoplayback_direct(env) : Bool
    host = env.request.query_params["host"]?
    return false unless host && host.ends_with?(".googlevideo.com")

    query = env.request.query
    range = env.request.headers["Range"]?

    5.times do
      break unless host.ends_with?(".googlevideo.com")

      client = HTTP::Client.new(host, tls: true)
      wrote = false
      begin
        client.connect_timeout = 5.seconds
        client.read_timeout = 30.seconds

        headers = HTTP::Headers.new
        headers["Range"] = range if range

        redirect = nil

        client.get("/videoplayback?#{query}", headers) do |resp|
          if resp.status_code.in?(301, 302, 303, 307, 308) && (location = resp.headers["Location"]?)
            redirect = URI.parse(location)
            next
          end

          env.response.status_code = resp.status_code
          resp.headers.each do |key, value|
            next if {"transfer-encoding", "connection", "keep-alive"}.includes?(key.downcase)
            env.response.headers[key] = value
          end
          wrote = true
          IO.copy resp.body_io, env.response
        end

        if redirect
          next_host = redirect.as(URI).host
          next_query = redirect.as(URI).query
          break unless next_host && next_query
          host = next_host
          query = next_query
          next
        end

        return true
      rescue
        # If the response already started, the connection is broken either way
        # and the caller must not try to write an error into it; only fall back
        # when nothing has been sent yet.
        return wrote
      ensure
        client.close
      end
    end

    # Redirect loop, a hop outside googlevideo, or no Location to follow:
    # fall back to the companion relay rather than forwarding a redirect to
    # the client ourselves.
    false
  end
end
