require 'github/markup'
puts '<link rel="stylesheet" href="/css/github-markdown.css">'
puts '<div class="markdown-body">'
puts GitHub::Markup.render('API.md', File.read('API.md'))
puts '</div>'
