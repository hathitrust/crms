function redirHome()   { window.location = "crms"; }
function redirReview() { window.location = "crms?p=review"; }
function redirExpert() { window.location = "crms?p=expert"; }

function changeFrame1(doSize) {
  var sel = document.getElementById("search1Select");
  var url = sel.options[sel.selectedIndex].value;
  var tf = document.getElementById("tFrame");
  if (tf.src != url) { tf.src = url; }
  if (doSize)
  {
    tf.style.display = "block";
    document.getElementById("bFrame").style.display = "none";
  }
}

function changeFrame2(doSize) {
  var sel = document.getElementById("search2Select");
  var url = sel.options[sel.selectedIndex].value;
  var bf = document.getElementById("bFrame");
  if (bf.src != url) { bf.src = url; }
  if (doSize)
  {
    bf.style.display = "block";
    document.getElementById("tFrame").style.display = "none";
  }
}

function flipFrame()
{
  var tf = document.getElementById("tFrame");
  var bf = document.getElementById("bFrame");
  if (tf.style.display == "none")
  {
    tf.style.display = "block";
    bf.style.display = "none";
  }
  else
  {
    tf.style.display = "none";
    bf.style.display = "block";
  }
}

function popRenewalDate()
{
  var req = null;
  var renNum = document.getElementById('renNum');
  var renDate = document.getElementById('renDate');
  var id  = renNum.value;
  renDate.value = "Searching...";
  if (window.XMLHttpRequest)
  {
    req = new XMLHttpRequest();
  }
  else if (window.ActiveXObject)
  {
    try {
        req = new ActiveXObject("Msxml2.XMLHTTP");
    } catch (e)
    {
        try {
            req = new ActiveXObject("Microsoft.XMLHTTP");
        } catch (e) {}
    }
  }
  req.onreadystatechange = function()
  {
    if (req.readyState == 4)
    {
      if (req.status == 200)
      {
        renDate.value = req.responseText;
      }
      else
      {
        renDate.value = "";
      }
    }
  };
  req.open("GET", "/cgi/c/crms/getRenewalDate?id=" + id, true);
  req.send(null);
}

function popReviewInfo(id,user,sys)
{
  var req = null;
  var loader = document.getElementById('loader' + user);

  if (window.XMLHttpRequest)
  {
    req = new XMLHttpRequest();
  }
  else if (window.ActiveXObject)
  {
    try {
        req = new ActiveXObject("Msxml2.XMLHTTP");
    } catch (e)
    {
        try {
            req = new ActiveXObject("Microsoft.XMLHTTP");
        } catch (e) {}
    }
  }
  req.onreadystatechange = function()
  {
    if (req.readyState == 4)
    {
      if (req.status == 200)
      {
        var data = JSON.parse(req.responseText, null);
        if (data)
        {
          var button = document.getElementById("r" + data.rights);
          if (button) { button.checked = "checked"; }
          button = document.getElementById("renewalFieldCheckbox");
          if (button) { button.checked = (data.renNum != null); }
          document.submitReview.renDate.value = data.renDate;
          document.submitReview.note.value = data.note;
          selMenuItem('catMenu',(data.category)? data.category:'');
        }
      }
      else {}
      if (loader) { loader.style.display='none'; }
    }
  };
  if (loader) { loader.style.display=''; }
  req.open("GET", "/cgi/c/crms/getReviewInfo?id=" + id + ";user=" + user + ";sys=" + sys, true);
  req.send(null);
}

function PredictRights(id)
{
  var year = document.getElementById("renewalField").value;
  var isPub = (document.getElementById('renewalFieldCheckbox').checked)? 1:0;
  var cat = SelectedCategory();
  var isCrown = (cat == 'Crown Copyright')? 1:0;
  /*var actualPubField = document.getElementById('actualPubDateField');
  var actualPub;
  if (actualPubField)
  {
    actualPub = actualPubField.value;
  }
  if (actualPub == null)
  {
    actualPubField = document.getElementById('pubDateSpan');
    if (actualPubField)
    {
      actualPub = actualPubField.value;
    }
  }*/
  var req = null;
  var rights = document.getElementsByName("rights");
  var sel = GetCheckedValue(rights);
  // There is a hidden div that tells us which button id is und/nfi
  var und = document.getElementById('UNDNFI').title;
  // Backed out in favor of submission rules TBD.
  /*if (und && cat == 'Translation')
  {
    var button = document.getElementById('r' + und);
    if (button) { button.checked = "checked"; }
    return;
  }*/
  if (und && sel == und) { return; }
  if (window.XMLHttpRequest)
  {
    req = new XMLHttpRequest();
  }
  else if (window.ActiveXObject)
  {
    try {
        req = new ActiveXObject("Msxml2.XMLHTTP");
    } catch (e)
    {
        try {
            req = new ActiveXObject("Microsoft.XMLHTTP");
        } catch (e) {}
    }
  }
  req.onreadystatechange = function()
  {
    if (req.readyState == 4 && req.status == 200)
    {
      if (req.responseText)
      {
        sel = GetCheckedValue(rights);
        und = document.getElementById('UNDNFI').title;
        if (und && sel == und) { return; }
        if (!und || sel != und)
        {
          if (sel != "")
          {
            var button = document.getElementById("r" + sel);
            button.checked = "";
          }
          var button = document.getElementById("r" + req.responseText);
          if (button) { button.checked = "checked" }
        }
      }
    }
  };
  var url = "/cgi/c/crms/predictRights?sys=crmsworld;id=" +
            id + ";year=" + year + ";ispub=" + isPub +
            ";crown=" + isCrown;
  //if (actualPub) url += ";pub=" + actualPub;
  req.open("GET", url, true);
  req.send(null);
}

function PredictDate(id)
{
  var rf = document.getElementById("renewalField2");
  var year = rf.value;
  var span = document.getElementById("renewalSpan2");
  if (year.length == 0)
  {
    span.innerHTML = '';
    return;
  }
  //var isPub = (document.getElementById('renewalFieldCheckbox2').checked)? 1:0;
  //var cat = SelectedCategory();
  //var isCrown = (cat == 'Crown Copyright')? 1:0;
  /*var actualPubField = document.getElementById('actualPubDateField');
  var actualPub;
  if (actualPubField)
  {
    actualPub = actualPubField.value;
  }*/
  var req = null;
  span.innerHTML = "Calculating...";
  if (window.XMLHttpRequest)
  {
    req = new XMLHttpRequest();
  }
  else if (window.ActiveXObject)
  {
    try {
        req = new ActiveXObject("Msxml2.XMLHTTP");
    } catch (e)
    {
        try {
            req = new ActiveXObject("Microsoft.XMLHTTP");
        } catch (e) {}
    }
  }
  req.onreadystatechange = function()
  {
    if (req.readyState == 4)
    {
      if (req.status == 200)
      {
        var txt = req.responseText;
        span.innerHTML = txt;
      }
      else
      {
        span.innerHTML = '';
      }
    }
  };
  var url = "/cgi/c/crms/predictRights?sys=crmsworld;doyear=1;id=" +
            id + ";year=" + year;
  //if (actualPub) url += ";pub=" + actualPub;
  req.open("GET", url, true);
  req.send(null);
}

function ShowPopup(hoveritem)
{
  hp = document.getElementById("hoverpopup");

  // Set position of hover-over popup
  hp.style.top = hoveritem.offsetTop + 18;
  hp.style.left = hoveritem.offsetLeft + 20;

  // Set popup to visible
  hp.style.visibility = "Visible";
}

function HidePopup()
{
  hp = document.getElementById("hoverpopup");
  hp.style.visibility = "none";
}

function change()
{
  hp = document.getElementById("test");
  hp.style.color = "blue";
}

function toggle()
{
  hp = document.getElementById(1);
  var color = hp.checked? "red" : "red";
  hp.style.color = color;
}

function ToggleADD()
{
  var lab = document.getElementById("renewalFieldLabel");
  var cb = document.getElementById("renewalFieldCheckbox");
  var field = document.getElementById("renewalField");
  lab.innerHTML = (cb.checked)? "Publication&nbsp;Date:":"Author&nbsp;Death&nbsp;Date:";
  field.title = (cb.checked)? "Publication Date":"Author Death Date";
  /*var actualPubRow = document.getElementById('actualPubRow');
  if (actualPubRow)
  {
    actualPubRow.style.display = (cb.checked)? "none":"table-row";
    var actualPubField = document.getElementById('actualPubDateField');
    if (actualPubField && cb.checked)
    {
      // not sure about this; it is destructive
      //field.value = actualPubField.value;
    }
  }*/
}

function VerifyCategory()
{
  if (gSys == 'crms')
  {
    var rights = document.getElementsByName("rights");
    var sel = GetCheckedValue(rights);
    if (sel == "7")
    {
      return (confirm('Please confirm that this work is, or is derived from, a non-US publication from 1871-1922.'));
    }
  }
  var sel = SelectedCategory();
  if (sel == "Missing" || sel == "Wrong Record")
  {
    if (!document.getElementById("CorrectionWarning"))
    {
      return (confirm('Please confirm that you have submitted a Feedback report within the PageTurner.'));
    }
  }
  return true;
}

function SelectedCategory()
{
  var cat = document.getElementById("catMenu");
  return cat.options[cat.selectedIndex].value;
}

// return the value of the radio button that is checked
// return an empty string if none are checked, or
// there are no radio buttons
function GetCheckedValue(radioObj)
{
  if (!radioObj) { return ""; }
  var radioLength = radioObj.length;
  if (radioLength == undefined)
  {
    if (radioObj.checked) { return radioObj.value; }
    else { return ""; }
  }
  var i;
  for (i = 0; i < radioLength; i++)
  {
    if (radioObj[i].checked) { return radioObj[i].value; }
  }
  return "";
}

function zoom(selector,name)
{
  var val = selector.options[selector.selectedIndex].value;
  setCookie(name,val,365);
  document.location.search = document.location.search;
  document.getElementById('tFrame').contentWindow.location.reload(true);
}

function PullPubDate()
{
  var date = document.getElementById('pubDateSpan').innerHTML;
  var re = /^\s*(-?\d+)(--?\d+)?\s*$/;
  var a = re.exec(date);
  if (a.length > 1) { date = a[1]; }
  else { date = ''; }
  document.getElementById('renewalField').value=date;
}


