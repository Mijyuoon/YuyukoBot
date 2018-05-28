# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'htmlentities'
require 'uri'

module Search
  extend Yuyuko::CommandContainer

  def self.sanitize(text, html = false)
    if html
      @html_coder ||= HTMLEntities.new
      text = @html_coder.decode(text)
      text = text.gsub(/<[^>]+>/, '')
    end

    text.gsub(/([*_~`])/, %q(\\\1))
  end

  def self.google_search(query, offset: 0)
    params = URI.encode_www_form({hl: 'en', q: query, start: offset})

    useragent = Yuyuko.cfg('mod.search.user_agent').sample
    header = { 'User-Agent' => useragent }

    connection = Net::HTTP.new('www.google.co.uk', 443)
    connection.use_ssl = true

    request = connection.get("/search?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('#rso div.rc').map do |x|
      link, summ = x.css('h3.r > a').first, x.css('div.s span.st').first
      (link && summ) ? {u: link[:href], h: link.content, s: summ.content} : nil
    end.delete_if(&:nil?)
  rescue
    []
  end

  def self.google_images(query)
    params = URI.encode_www_form({hl: 'en', tbm: 'isch', q: query})

    useragent = Yuyuko.cfg('mod.search.user_agent').sample
    header = { 'User-Agent' => useragent }

    connection = Net::HTTP.new('www.google.co.uk', 443)
    connection.use_ssl = true

    request = connection.get("/search?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('div.rg_meta').map {|x| JSON.parse(x.content)['ou'] }
  rescue
    []
  end

  def self.youtube_search(query)
    params = URI.encode_www_form({hl: 'en', search_query: query})

    useragent = Yuyuko.cfg('mod.search.user_agent').sample
    header = { 'User-Agent' => useragent }

    connection = Net::HTTP.new('www.youtube.com', 443)
    connection.use_ssl = true

    request = connection.get("/results?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('#img-preload > img').map do |x|
      url = x[:src].match(%r{/vi/([\w-]+)/})
      url ? "https://youtu.be/#{url[1]}" : nil
    end.delete_if(&:nil?).uniq
  rescue
    []
  end

  SEARCH_PAGE_LENGTH = 3

  command_group('Search', delay: 5.0)

  command(%w[google gsearch g],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.gsearch.usage',
  description: 'mod.search.help.gsearch.desc') do |evt, query|
    message = evt.channel.send_embed('mod.search.embed.gsearch.wait',
     username: evt.user.nickname, usericon: evt.user.avatar_url)

    results = google_search(query)
    if results.empty?
      message.edit_embed('mod.search.embed.gsearch.empty',
        username: evt.user.nickname, usericon: evt.user.avatar_url)
      next
    end

    results_pages = (results.length.to_f / SEARCH_PAGE_LENGTH).ceil

    results = results.each_with_index.map do |x, i|
      head = sanitize(x[:h], true)
      summ = sanitize(x[:s], true)
      "**#{i+1}. [#{head}](#{x[:u]})**\n#{summ}"
    end

    message.interactive_paginate(results_pages,
    delete: true, owner: evt.message.author) do |index|
      label = Yuyuko.tr('mod.search.gsearch.result', query: query)
      body = results.slice((index - 1) * SEARCH_PAGE_LENGTH, SEARCH_PAGE_LENGTH)
      body = "#{label}\n\n#{body.join("\n\n")}"

      message.edit_embed('mod.search.embed.gsearch.result',
        username: evt.user.nickname, usericon: evt.user.avatar_url,
        body: body, index: index, total: results_pages)
    end
  end

  command(%w[google-img gimages gi],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.gimages.usage',
  description: 'mod.search.help.gimages.desc') do |evt, query|
    message = evt.channel.send_embed('mod.search.embed.gimages.wait',
      username: evt.user.nickname, usericon: evt.user.avatar_url)

    results = google_images(query)
    if results.empty?
      message.edit_embed('mod.search.embed.gimages.empty',
        username: evt.user.nickname, usericon: evt.user.avatar_url)
      next
    end

    message.interactive_paginate(results.length,
    delete: true, owner: evt.message.author) do |index|
      message.edit_embed('mod.search.embed.gimages.result',
        username: evt.user.nickname, usericon: evt.user.avatar_url,
        query: query, image: results[index-1], index: index, total: results.length)
    end
  end

  command(%w[youtube ytsearch yt],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.ytsearch.usage',
  description: 'mod.search.help.ytsearch.desc') do |evt, query|
    message = evt.channel.send_message(text: Yuyuko.tr('mod.search.ytsearch.wait', user: evt.user))

    results = youtube_search(query)
    if results.empty?
      message.edit(text: Yuyuko.tr('mod.search.ytsearch.empty', user: evt.user))
      next
    end

    message.interactive_paginate(results.length,
    delete: true, owner: evt.message.author) do |index|
      message.edit(text: Yuyuko.tr('mod.search.ytsearch.result',
        user: evt.user, url: results[index-1], index: index, total: results.length))
    end
  end
  
  command(%w[lmgtfy lg],
    arg_mode: :concat, arg_types: [:string],
    usage_info: 'mod.search.help.lmgtfy.usage',
    description: 'mod.search.help.lmgtfy.desc') do |evt, query|
      evt.channel.send_message(text: "https://lmgtfy.com/?q=#{URI.escape(query)}", user: evt.user))
  end
end
