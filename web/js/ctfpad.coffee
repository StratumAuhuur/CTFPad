$ ->
  proto = if location.protocol is 'http:' then 'ws' else 'wss'
  sock = new WebSocket "#{proto}#{location.href.substring location.protocol.length-1, location.href.lastIndexOf '/'}/ws/"
  sock.onopen = ->
    sock.send "\"#{sessid}\""
    sock.onclose = ->
      unless window.preventSocketAlert
        alert 'the websocket has been disconnected, reloading the page'
        document.location.reload()
    sock.onmessage = (event) ->
      msg = JSON.parse event.data
      console.log msg
      if msg.type is 'done'
        self = $("input[data-chalid='#{msg.subject}']")
        self.prop 'checked', msg.data
        self.parent().next().css 'text-decoration', if msg.data then 'line-through' else 'none'
        if msg.data
          self.parent().parent().addClass 'done'
        else
          self.parent().parent().removeClass 'done'
        updateProgress()
      else if msg.type is 'assign'
        self = $(".labels[data-chalid='#{msg.subject}']")
        if msg.data[1]
          self.append $("<li />").append($("<span />").addClass("label").attr("data-name", msg.data[0].name).text(msg.data[0].name))
        else
          self.find(".label[data-name='#{msg.data[0].name}']").parent().remove()
        $(".assignment-count[data-chalid='#{msg.subject}']").text self.first().find('.label').length
      else if msg.type is 'ctfmodification'
        $('#ctfmodification').fadeIn 500
      else if msg.type is 'login'
        $('#userlist').append $("<li />").text(msg.data)
        $('#usercount').text $('#userlist').children('li').length
      else if msg.type is 'logout'
        $("#userlist li:contains('#{msg.data}')").remove()
        $('#usercount').text $('#userlist').children('li').length
      else if msg.type is 'fileupload' or msg.type is 'filedeletion'
        if "#{msg.data}files" is window.currentPage
          current = window.currentPage
          window.currentPage = null
          $(".contentlink[href='##{current}']").click()
        subject = $(".contentlink[href='##{msg.data}files']")
        if msg.filecount > 0
          subject.children('i').removeClass('icon-folder-close').addClass('icon-folder-open')
        else
          subject.children('i').removeClass('icon-folder-open').addClass('icon-folder-close')
        subject.nextAll('sup').text msg.filecount
      else
        alert event.data
      #TODO handle events

  window.onbeforeunload = ->
    window.preventSocketAlert = true
    return

  sessid = $.cookie 'ctfpad'
  if $.cookie('ctfpad_hide') is undefined then $.cookie 'ctfpad_hide', 'false'

  updateProgress = ->
    #challenge progress
    d = $('.challenge.done').length / $('.challenge').length
    $('#progress').css 'width', "#{d*100}%"
    $('#progress').siblings('span').text "#{$('.challenge.done').length} / #{$('.challenge').length}"
    #score progress
    totalScore = 0
    score = 0
    $('.challenge').each ->
      totalScore += parseInt($(this).attr 'data-chalpoints')
      if $(this).hasClass 'done' then score += parseInt($(this).attr 'data-chalpoints')
    $('#scoreprogress').css 'width', "#{(score/totalScore)*100}%"
    $('#scoreprogress').siblings('span').text "#{score} / #{totalScore}"
    #categories progress
    $('.category').each ->
      cat = $(this).attr 'data-category'
      done = $(this).siblings(".done[data-category='#{cat}']").length
      $(this).find('.done-count').text done

  updateProgress()

  window.uploads = []

  window.upload_refresh = (remove) ->
    if remove
      window.uploads.splice(window.uploads.indexOf(remove), 1)
      if window.uploads.length == 0
        $('#uploadbutton').hide()
        return
    total_size = total_prog = 0
    for upload in window.uploads
      total_size += upload.file.size
      total_prog += upload.progress
    progress = parseInt(total_prog / total_size * 100, 10)
    $('#uploadprogress').text "#{progress}% / #{window.uploads.length} files"

  window.upload_handler_send = (e, data) ->
    if window.uploads.length == 0
      $('#uploadbutton').show()
    data.context =
      file: data.files[0]
      progress: 0
    window.uploads.push data.context
    window.upload_refresh()

  window.upload_handler_done = (e, data) ->
    window.upload_refresh(data.context)

  window.upload_handler_fail = (e, data) ->
    window.upload_refresh(data.context)
    alert "Upload failed: #{data.errorThrown}"

  window.upload_handler_progress = (e, data) ->
    data.context.progress = data.loaded
    window.upload_refresh()


  $('.contentlink').click ->
    page = $(this).attr('href').replace '#', ''
    unless window.currentPage is page
      if m = /^(ctf|challenge)(.+)files$/.exec(page)
        $('#content').html ""
        $.get "/files/#{m[1]}/#{m[2]}", (data) ->
          $('#content').html data
          url = "/upload/#{m[1]}/#{m[2]}"
          $('#fileupload').fileupload({
            url: url,
            dataType: 'json',
            send: window.upload_handler_send,
            done: window.upload_handler_done,
            fail: window.upload_handler_fail,
            progress: window.upload_handler_progress
          }).prop('disabled', !$.support.fileInput).parent().addClass $.support.fileInput ? undefined : 'disabled'
      else
        $('#content').pad {'padId':page}
      $(".highlighted").removeClass("highlighted")
      $(this).parents(".highlightable").addClass("highlighted")
      window.currentPage = page

  $(".contentlink[href='#{location.hash}']").click()

  $("input[type='checkbox']").change ->
    $(this).parent().next().css 'text-decoration',if this.checked then 'line-through' else 'none'
    sock.send JSON.stringify {type:'done', subject:parseInt($(this).attr('data-chalid')), data:this.checked}

  $('.assignments').popover({html:true, content: -> $(this).parent().find('.popover-content').html()}).click (e)->
    $('.assignments').not(this).popover('hide')
    $(this).popover 'toggle'
    e.stopPropagation()
  $('html').click ->
    $('.assignments').popover('hide')


  $('.scoreboard-toggle').popover {html: true, content: ->
    $.get '/scoreboard', (ans) -> #FIXME function gets executed twice?
      $('#scoreboard').html(ans)
    , 'html'
    return '<span id="scoreboard">loading...</span>'
  }

  $('body').delegate '.btn-assign', 'click', ->
    sock.send JSON.stringify {type:'assign', subject:parseInt($(this).attr('data-chalid'))}

  $('body').delegate '.add-challenge', 'click', ->
    a = $(this).parent().clone()
    a.find('input').val('').removeClass 'hide'
    $(this).parent().after a
    if a.hasClass 'dummy'
      a.removeClass('dummy')
      $(this).parent().remove()

  $('body').delegate '.remove-challenge', 'click', ->
    if $('.category-formgroup').length > 1 then $(this).parent().remove()

  $('body').delegate '.deletefile', 'click', ->
    fileid = $(this).attr('data-id')
    filename = $(this).attr('data-name')
    $('#deletefilemodal .alert').removeClass('alert-success alert-error').hide()
    $('#deletefilename').text filename
    $('#deletefilebtnno').text 'no'
    $('#deletefilebtnyes').show()
    $('#deletefilemodal').data('fileid', fileid).modal 'show'
    return false

  $('#hidefinished').click ->
    unless $(this).hasClass 'active'
      $('head').append '<style id="hidefinishedcss">.done { display:none; }</style>'
      $.cookie 'ctfpad_hide', 'true'
    else
      $('#hidefinishedcss').remove()
      $.cookie 'ctfpad_hide', 'false'
  if $.cookie('ctfpad_hide') is 'true' then $('#hidefinished').click()

  window.newctf = ->
    l = $('#ctfform').serializeArray()
    newctf = {title: l.shift().value, challenges:[]}
    until l.length is 0
      newctf.challenges.push {'title':l.shift().value, 'category':l.shift().value, 'points':parseInt(l.shift().value)}
    sock.send JSON.stringify {type:'newctf', data: newctf}
    $('#ctfmodal').modal 'hide'
    $('#ctfform').find('input').val ''
    document.location = '/scope/latest'

  window.ajaxPost = (url, data = null, cb) -> $.ajax

  window.changepw = ->
    $.ajax {
      url: '/changepassword'
      type: 'post'
      data: $('#passwordform').serialize()
      dataType: 'json'
      headers:
        'x-session-id': $.cookie('ctfpad')
      success: (ans) ->
        $('#passwordmodal .alert').removeClass('alert-success alert-error')
        if ans.success
          $('#passwordmodal .alert').addClass('alert-success').text 'your password has been changed'
        else
          $('#passwordmodal .alert').addClass('alert-error').text ans.error
        $('#passwordmodal .alert').show()
    }

  window.newapikey = ->
    $.ajax {
      url: '/newapikey'
      type: 'post'
      dataType: 'text'
      headers:
        'x-session-id': $.cookie('ctfpad')
      success: (apikey) ->
        if apikey then $('#apikey').text apikey
    }

  window.modifyctf = ->
    l = $('#ctfmodifyform').serializeArray()
    ctf = {ctf: window.current.id, challenges:[]}
    until l.length is 0
      ctf.challenges.push {'id':parseInt(l.shift().value), 'title':l.shift().value, 'category':l.shift().value, 'points':parseInt(l.shift().value)}
    sock.send JSON.stringify {type:'modifyctf', data: ctf}
    $('#ctfmodifymodal').modal 'hide'
    setTimeout ->
      document.location.reload()
    ,500

  window.delete_file_confirmed = () ->
    $.get '/delete_file/' + $('#deletefilemodal').data('fileid'), (ans) ->
      $('#deletefilemodal .alert').removeClass('alert-success alert-error')
      if ans.success
        $('#deletefilemodal .alert').addClass('alert-success').text 'file has been deleted'
      else
        $('#deletefilemodal .alert').addClass('alert-error').text ans.error
      $('#deletefilemodal .alert').show()
      $('#deletefilebtnno').text('close')
      $('#deletefilebtnyes').hide()
    ,'json'

