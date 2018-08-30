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
  var renNum = document.getElementById('renewalField');
  var renDate = document.getElementById('getDate');
  var id  = renNum.value;
  renDate.value = "Searching...";
  var req = new XMLHttpRequest();
  req.onreadystatechange = function()
  {
    if (req.readyState == 4)
    {
      var icren = document.getElementById('ICREN');
      var button;
      if (icren)
      {
        button = document.getElementById("r" + icren.title);
      }
      if (req.status == 200)
      {
        var rights = document.getElementsByName("rights");
        var sel = GetCheckedValue(rights);
        var und = document.getElementById('UNDNFI').title;
        renDate.value = req.responseText;
        if (und && sel == und) { return; }
        if (button) { button.checked = "checked"; }
      }
      else
      {
        renDate.value = "";
        if (button) { button.checked = ""; }
      }
    }
  };
  req.open("GET", gCGI + "getRenewalDate?id=" + id, true);
  req.send(null);
}

function PredictRights(id)
{
  var img = document.getElementById("predictionLoader");
  var year = document.getElementById("renewalField").value;
  var isPub = (document.getElementById('renewalFieldCheckbox').checked)? 1:0;
  var cat = SelectedCategory();
  var isCrown = (cat == 'Crown Copyright')? 1:0;
  var actualPubField = document.getElementById('actualPubDateField');
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
  }
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
  if (img) { img.style.display = 'block'; }
  var req = new XMLHttpRequest();
  req.onreadystatechange = function()
  {
    if (req.readyState == 4 && req.status == 200)
    {
      if (img) { img.style.display = 'none'; }
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
        if (req.responseText)
        {
          var button = document.getElementById("r" + req.responseText);
          if (button) { button.checked = "checked"; }
        }
      }
    }
  };
  var url = gCGI + "predictRights?sys=crmsworld;id=" +
            id + ";year=" + year + ";ispub=" + isPub +
            ";crown=" + isCrown;
  if (actualPub) { url += ";pub=" + actualPub; }
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
  var actualPubField = document.getElementById('actualPubDateField');
  var actualPub;
  if (actualPubField)
  {
    actualPub = actualPubField.value;
  }
  span.innerHTML = "Calculating...";
  var req = new XMLHttpRequest();
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
  var url = gCGI + "predictRights?sys=crmsworld;doyear=1;id=" +
            id + ";year=" + year;
  if (actualPub) url += ";pub=" + actualPub;
  req.open("GET", url, true);
  req.send(null);
}

function ToggleADD()
{
  var lab = document.getElementById("renewalFieldLabel");
  var cb = document.getElementById("renewalFieldCheckbox");
  var field = document.getElementById("renewalField");
  var actualPubRow = document.getElementById('actualPubRow');
  lab.innerHTML = (cb.checked)? ((actualPubRow)? "Actual&nbsp;Pub&nbsp;Date":"Publication&nbsp;Date:"):"Author&nbsp;Death&nbsp;Date:";
  field.title = (cb.checked)? "Publication Date":"Author Death Date";
  if (actualPubRow)
  {
    actualPubRow.style.display = (cb.checked)? "none":"table-row";
    var actualPubField = document.getElementById('actualPubDateField');
    if (actualPubField && cb.checked && actualPubField.value)
    {
      // not sure about this; it is destructive
      field.value = actualPubField.value;
      actualPubField.value = "";
    }
  }
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
  if (!radioObj) { return null; }
  var radioLength = radioObj.length;
  if (radioLength == undefined)
  {
    if (radioObj.checked) { return radioObj.value; }
    else { return null; }
  }
  var i;
  for (i = 0; i < radioLength; i++)
  {
    if (radioObj[i].checked) { return radioObj[i].value; }
  }
  return null;
}

function zoom(selector,name)
{
  var val = selector.options[selector.selectedIndex].value;
  setCookie(name,val,365);
  document.location.search = document.location.search;
  document.getElementById('tFrame').contentWindow.location.reload(true);
  //document.getElementById('tFrame').src = document.getElementById('tFrame').src;
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

function Debug(msg, append)
{
  var el = document.getElementById('debugArea');
  if (el)
  {
    if (append)
    {
      msg = el.innerHTML + "<br/>\n" + msg;
    }
    el.innerHTML = msg;
  }
}
