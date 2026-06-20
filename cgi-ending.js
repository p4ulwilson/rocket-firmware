if(_liveTestStream){ _liveTestStream.getTracks().forEach(function(t){ t.stop(); }); _liveTestStream=null; }
  var vid  = document.getElementById('live-test-video');
  var btn  = document.getElementById('live-test-btn');
  var stop = document.getElementById('live-test-stop');
  var msg  = document.getElementById('live-test-msg');
  if(vid)  { vid.srcObject=null; vid.style.display='none'; }
  if(btn)  btn.style.display  = 'inline-block';
  if(stop) stop.style.display = 'none';
  if(msg)  msg.textContent    = '';
}

function acctShowInviteCode(){
  fetch('/cgi-bin/rocket?user_invite_code')
    .then(function(r){ return r.json(); })
    .then(function(d){
      var hint = document.getElementById('acct-invite-hint');
      var inp  = document.getElementById('acct-inp-invite');
      if(d.code){
        if(hint) hint.innerHTML = '&#x1F511; Your mesh invite code: <strong style="color:#3fb950;font-family:monospace">'+d.code+'</strong> &mdash; share with people you want to invite.';
        if(inp)  inp.value = d.code;
      } else {
        if(hint) hint.textContent = 'Could not load — SSH to router and check conduit.toml';
      }
    })
    .catch(function(){
      var hint = document.getElementById('acct-invite-hint');
      if(hint) hint.textContent = 'Network error loading invite code.';
    });
}

</script>
</body>
</html>
