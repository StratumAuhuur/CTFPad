// Generated by CoffeeScript 1.8.0
(function() {
  $(function() {
    var sessid, sock, updateProgress;
    sock = new WebSocket("wss" + (location.href.substring(location.protocol.length - 1, location.href.lastIndexOf('/'))));
    sock.onopen = function() {
      sock.send("\"" + sessid + "\"");
      sock.onclose = function() {
        if (!window.preventSocketAlert) {
          alert('the websocket has been disconnected, reloading the page');
          return document.location.reload();
        }
      };
      return sock.onmessage = function(event) {
        var current, msg, self, subject;
        msg = JSON.parse(event.data);
        console.log(msg);
        if (msg.type === 'done') {
          self = $("input[data-chalid='" + msg.subject + "']");
          self.prop('checked', msg.data);
          self.parent().next().css('text-decoration', msg.data ? 'line-through' : 'none');
          if (msg.data) {
            self.parent().parent().addClass('done');
          } else {
            self.parent().parent().removeClass('done');
          }
          return updateProgress();
        } else if (msg.type === 'assign') {
          self = $(".labels[data-chalid='" + msg.subject + "']");
          if (msg.data[1]) {
            self.append($("<li />").append($("<span />").addClass("label").attr("data-name", msg.data[0].name).text(msg.data[0].name)));
          } else {
            self.find(".label[data-name='" + msg.data[0].name + "']").parent().remove();
          }
          return $(".assignment-count[data-chalid='" + msg.subject + "']").text(self.first().find('.label').length);
        } else if (msg.type === 'ctfmodification') {
          return $('#ctfmodification').fadeIn(500);
        } else if (msg.type === 'login') {
          $('#userlist').append($("<li />").text(msg.data));
          return $('#usercount').text($('#userlist').children('li').length);
        } else if (msg.type === 'logout') {
          $("#userlist li:contains('" + msg.data + "')").remove();
          return $('#usercount').text($('#userlist').children('li').length);
        } else if (msg.type === 'fileupload' || msg.type === 'filedeletion') {
          if (("" + msg.data + "files") === window.currentPage) {
            current = window.currentPage;
            window.currentPage = null;
            $(".contentlink[href='#" + current + "']").click();
          }
          subject = $(".contentlink[href='#" + msg.data + "files']");
          if (msg.filecount > 0) {
            subject.children('i').removeClass('icon-folder-close').addClass('icon-folder-open');
          } else {
            subject.children('i').removeClass('icon-folder-open').addClass('icon-folder-close');
          }
          return subject.nextAll('sup').text(msg.filecount);
        } else {
          return alert(event.data);
        }
      };
    };
    window.onbeforeunload = function() {
      window.preventSocketAlert = true;
    };
    sessid = $.cookie('ctfpad');
    if ($.cookie('ctfpad_hide') === void 0) {
      $.cookie('ctfpad_hide', 'false');
    }
    updateProgress = function() {
      var d, score, totalScore;
      d = $('.challenge.done').length / $('.challenge').length;
      $('#progress').css('width', "" + (d * 100) + "%");
      $('#progress').siblings('span').text("" + ($('.challenge.done').length) + " / " + ($('.challenge').length));
      totalScore = 0;
      score = 0;
      $('.challenge').each(function() {
        totalScore += parseInt($(this).attr('data-chalpoints'));
        if ($(this).hasClass('done')) {
          return score += parseInt($(this).attr('data-chalpoints'));
        }
      });
      $('#scoreprogress').css('width', "" + ((score / totalScore) * 100) + "%");
      $('#scoreprogress').siblings('span').text("" + score + " / " + totalScore);
      return $('.category').each(function() {
        var cat, done;
        cat = $(this).attr('data-category');
        done = $(this).siblings(".done[data-category='" + cat + "']").length;
        return $(this).find('.done-count').text(done);
      });
    };
    updateProgress();
    window.uploads = [];
    window.upload_refresh = function(remove) {
      var progress, total_prog, total_size, upload, _i, _len, _ref;
      if (remove) {
        window.uploads.splice(window.uploads.indexOf(remove), 1);
        if (window.uploads.length === 0) {
          $('#uploadbutton').hide();
          return;
        }
      }
      total_size = total_prog = 0;
      _ref = window.uploads;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        upload = _ref[_i];
        total_size += upload.file.size;
        total_prog += upload.progress;
      }
      progress = parseInt(total_prog / total_size * 100, 10);
      return $('#uploadprogress').text("" + progress + "% / " + window.uploads.length + " files");
    };
    window.upload_handler_send = function(e, data) {
      if (window.uploads.length === 0) {
        $('#uploadbutton').show();
      }
      data.context = {
        file: data.files[0],
        progress: 0
      };
      window.uploads.push(data.context);
      return window.upload_refresh();
    };
    window.upload_handler_done = function(e, data) {
      return window.upload_refresh(data.context);
    };
    window.upload_handler_fail = function(e, data) {
      window.upload_refresh(data.context);
      return alert("Upload failed: " + data.errorThrown);
    };
    window.upload_handler_progress = function(e, data) {
      data.context.progress = data.loaded;
      return window.upload_refresh();
    };
    $('.contentlink').click(function() {
      var m, page;
      page = $(this).attr('href').replace('#', '');
      if (window.currentPage !== page) {
        if (m = /^(ctf|challenge)(.+)files$/.exec(page)) {
          $('#content').html("");
          $.get("/files/" + m[1] + "/" + m[2], function(data) {
            var url, _ref;
            $('#content').html(data);
            url = "/upload/" + m[1] + "/" + m[2];
            return $('#fileupload').fileupload({
              url: url,
              dataType: 'json',
              send: window.upload_handler_send,
              done: window.upload_handler_done,
              fail: window.upload_handler_fail,
              progress: window.upload_handler_progress
            }).prop('disabled', !$.support.fileInput).parent().addClass((_ref = $.support.fileInput) != null ? _ref : {
              undefined: 'disabled'
            });
          });
        } else {
          $('#content').pad({
            'padId': page
          });
        }
        $(".highlighted").removeClass("highlighted");
        $(this).parents(".highlightable").addClass("highlighted");
        return window.currentPage = page;
      }
    });
    $(".contentlink[href='" + location.hash + "']").click();
    $("input[type='checkbox']").change(function() {
      $(this).parent().next().css('text-decoration', this.checked ? 'line-through' : 'none');
      return sock.send(JSON.stringify({
        type: 'done',
        subject: parseInt($(this).attr('data-chalid')),
        data: this.checked
      }));
    });
    $('.assignments').popover({
      html: true,
      content: function() {
        return $(this).parent().find('.popover-content').html();
      }
    }).click(function(e) {
      $('.assignments').not(this).popover('hide');
      $(this).popover('toggle');
      return e.stopPropagation();
    });
    $('html').click(function() {
      return $('.assignments').popover('hide');
    });
    $('.scoreboard-toggle').popover({
      html: true,
      content: function() {
        $.get('/scoreboard', function(ans) {
          return $('#scoreboard').html(ans);
        }, 'html');
        return '<span id="scoreboard">loading...</span>';
      }
    });
    $('body').delegate('.btn-assign', 'click', function() {
      return sock.send(JSON.stringify({
        type: 'assign',
        subject: parseInt($(this).attr('data-chalid'))
      }));
    });
    $('body').delegate('.add-challenge', 'click', function() {
      var a;
      a = $(this).parent().clone();
      a.find('input').val('').removeClass('hide');
      $(this).parent().after(a);
      if (a.hasClass('dummy')) {
        a.removeClass('dummy');
        return $(this).parent().remove();
      }
    });
    $('body').delegate('.remove-challenge', 'click', function() {
      if ($('.category-formgroup').length > 1) {
        return $(this).parent().remove();
      }
    });
    $('body').delegate('.deletefile', 'click', function() {
      var fileid, filename;
      fileid = $(this).attr('data-id');
      filename = $(this).attr('data-name');
      $('#deletefilemodal .alert').removeClass('alert-success alert-error').hide();
      $('#deletefilename').text(filename);
      $('#deletefilebtnno').text('no');
      $('#deletefilebtnyes').show();
      $('#deletefilemodal').data('fileid', fileid).modal('show');
      return false;
    });
    $('#hidefinished').click(function() {
      if (!$(this).hasClass('active')) {
        $('head').append('<style id="hidefinishedcss">.done { display:none; }</style>');
        return $.cookie('ctfpad_hide', 'true');
      } else {
        $('#hidefinishedcss').remove();
        return $.cookie('ctfpad_hide', 'false');
      }
    });
    if ($.cookie('ctfpad_hide') === 'true') {
      $('#hidefinished').click();
    }
    window.newctf = function() {
      var l, newctf;
      l = $('#ctfform').serializeArray();
      newctf = {
        title: l.shift().value,
        challenges: []
      };
      while (l.length !== 0) {
        newctf.challenges.push({
          'title': l.shift().value,
          'category': l.shift().value,
          'points': parseInt(l.shift().value)
        });
      }
      sock.send(JSON.stringify({
        type: 'newctf',
        data: newctf
      }));
      $('#ctfmodal').modal('hide');
      $('#ctfform').find('input').val('');
      return document.location = '/scope/latest';
    };
    window.ajaxPost = function(url, data, cb) {
      if (data == null) {
        data = null;
      }
      return $.ajax;
    };
    window.changepw = function() {
      return $.ajax({
        url: '/changepassword',
        type: 'post',
        data: $('#passwordform').serialize(),
        dataType: 'json',
        headers: {
          'x-session-id': $.cookie('ctfpad')
        },
        success: function(ans) {
          $('#passwordmodal .alert').removeClass('alert-success alert-error');
          if (ans.success) {
            $('#passwordmodal .alert').addClass('alert-success').text('your password has been changed');
          } else {
            $('#passwordmodal .alert').addClass('alert-error').text(ans.error);
          }
          return $('#passwordmodal .alert').show();
        }
      });
    };
    window.newapikey = function() {
      return $.ajax({
        url: '/newapikey',
        type: 'post',
        dataType: 'text',
        headers: {
          'x-session-id': $.cookie('ctfpad')
        },
        success: function(apikey) {
          if (apikey) {
            return $('#apikey').text(apikey);
          }
        }
      });
    };
    window.modifyctf = function() {
      var ctf, l;
      l = $('#ctfmodifyform').serializeArray();
      ctf = {
        ctf: window.current.id,
        challenges: []
      };
      while (l.length !== 0) {
        ctf.challenges.push({
          'id': parseInt(l.shift().value),
          'title': l.shift().value,
          'category': l.shift().value,
          'points': parseInt(l.shift().value)
        });
      }
      sock.send(JSON.stringify({
        type: 'modifyctf',
        data: ctf
      }));
      $('#ctfmodifymodal').modal('hide');
      return setTimeout(function() {
        return document.location.reload();
      }, 500);
    };
    return window.delete_file_confirmed = function() {
      return $.get('/delete_file/' + $('#deletefilemodal').data('fileid'), function(ans) {
        $('#deletefilemodal .alert').removeClass('alert-success alert-error');
        if (ans.success) {
          $('#deletefilemodal .alert').addClass('alert-success').text('file has been deleted');
        } else {
          $('#deletefilemodal .alert').addClass('alert-error').text(ans.error);
        }
        $('#deletefilemodal .alert').show();
        $('#deletefilebtnno').text('close');
        return $('#deletefilebtnyes').hide();
      }, 'json');
    };
  });

}).call(this);
