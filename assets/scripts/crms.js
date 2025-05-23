import Highcharts from 'highcharts/esm/highcharts.js';

function setCookie(name,value,expiredays)
{
  var exdate = new Date();
  exdate.setDate(exdate.getDate()+expiredays);
  document.cookie = name + "=" + escape(value)+
    ((expiredays==null) ? "" : ";expires="+exdate.toGMTString());
}

export function loadChart(id, url) {
  var req = new XMLHttpRequest();
  req.onreadystatechange = function()
  { 
    if (req.readyState == 4)
    {
      if (req.status == 200)
      {
        var obj = document.getElementById(id);
        var data = JSON.parse(req.responseText);
		    Highcharts.chart(id, data);
		  }
      else    
      {
        alert("Error: "+url+" failed:"+req.status);
      }
    }
  };
  req.open("GET", url, true);
  req.send(null);
}

export function toggleVisibility(id) {
  var me = document.getElementById(id);
  if (me == null)
  {
    //alert("Can't get " + id);
  }
  else
  {
    if (me.style.display!="none") {me.style.display="none";}
    else {me.style.display="";}
  }
}

// Renamed from selMenuItem since this function is used everywhere.
// What if we just do this:
// document.getElementById(id).value = value
export function selectOption(id, value) {
  var me = document.getElementById(id);
  if (me == null)
  {
    //alert("Can't get " + id);
  }
  else
  {
    var i;
    for (i = 0; i < me.length; i++)
    {
      if (me.options[i].value == value)
      {
        me.selectedIndex = i;
        break;
      }
    }
  }
}

export function sfHover() {
  var sfEls = document.getElementById("menu").getElementsByTagName("li");
  for (var i=0; i<sfEls.length; i++)
  {
    sfEls[i].onmouseover=function()
    {
      this.className+=" sfhover";
    }
    sfEls[i].onmouseout=function()
    {
      this.className=this.className.replace(new RegExp(" sfhover\\b"), "");
    }
  }
  var sfAs = document.getElementById("menu").getElementsByTagName("a");
  for (var i=0; i<sfAs.length; i++)
  {
    sfAs[i].onmouseover=function()
    {
      this.className+=" sfhover";
    }
    sfAs[i].onmouseout=function()
    {
      this.className=this.className.replace(new RegExp(" sfhover\\b"), "");
    }
  }
}

// action code for debugger bars
export function toggleDiv(id, className)
{
  var el = document.getElementById(id);
  if (el.className == 'divHide') { el.className = className; }
  else { el.className = 'divHide'; }
}

// FIXME: this is unneeded compatibility code and callers should just call
// window.addEventListener instead.
// https://stackoverflow.com/questions/15564029/adding-to-window-onload-event
// Example: addEvent(window, 'load', myfunc);
export function addEvent(element, eventName, fn) {
  if (element.addEventListener)
  {
    element.addEventListener(eventName, fn, false);
  }
  else if (element.attachEvent)
  {
    element.attachEvent('on' + eventName, fn);
  }
}

export function changeFrame1(doSize) {
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

export function changeFrame2(doSize) {
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

export function flipFrame()
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

export function popRenewalDate()
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
      var pdusren = document.getElementById('PDUSREN');
      var icrenButton, pdusrenButton;
      if (icren)
      {
        icrenButton = document.getElementById("r" + icren.title);
      }
      if (icren)
      {
        pdusrenButton = document.getElementById("r" + pdusren.title);
      }
      if (req.status == 200)
      {
        var rights = document.getElementsByName("rights");
        var sel = GetCheckedValue(rights);
        var und = document.getElementById('UNDNFI').title;
        renDate.value = req.responseText;
        // PDUS if renewal is on or before the current year minus 69
        // So 1951 and earlier in 2020
        var cutoff = new String(new Date().getFullYear() - 69).slice(-2);
        var pdus = req.responseText.endsWith(cutoff);
        if (und && sel == und) { return; }
        if (pdus)
        {
          if (pdusrenButton) { pdusrenButton.checked = "checked"; }
        }
        else
        {
          if (icrenButton) { icrenButton.checked = "checked"; }
        }
      }
      else
      {
        renDate.value = "";
        if (icrenButton) { icrenButton.checked = ""; }
        if (pdusrenButton) { pdusrenButton.checked = ""; }
      }
    }
  };
  req.open("GET", ajaxURL("getRenewalDate") + "?id=" + id, true);
  req.send(null);
}

export async function predictRights(id, year, actualPubDate, pub, crown) {
  togglePredictionLoader(true);
  var url = ajaxURL("predictRights") + "?id=" + id + "&year=" + year +
            "&actual=" + actualPubDate + "&is_pub=" + pub + "&is_crown=" + crown;
  let response = await fetch(url);
  if (response.status === 200) {
    let data = await response.text();
    displayRightPrediction(data);
  }
  togglePredictionLoader(false);
}

// Internal function
// Display JSON response from predictRights CGI in the Commonwealth UI
function displayRightPrediction(data) {
  deselectCurrentRights();
  var json_data = JSON.parse(data);
  if (json_data.rights_id) {
    // Select radio button that corresponds to the appropriate crms.rights.id
    document.getElementById("r" + json_data.rights_id).checked = true;
  }
  // Display prediction logic (or error message)
  var span = document.getElementById("rights-description");
  if (span) {
    span.innerHTML = json_data.description;
  }
}

// Internal function
function deselectCurrentRights() {
  var rights = document.getElementsByName("rights");
  var sel = GetCheckedValue(rights);
  if (sel) {
    document.getElementById("r" + sel).checked = false;
  }
}

// Internal function
// ajaxURL("predictRights") => "https://babel.hathitrust.org/crms/cgi/predictRights"
function ajaxURL(target) {
  return window.location.protocol + "//" + window.location.host + "/crms/cgi/" + target;
}

// Internal function
function togglePredictionLoader(display) {
  var img = document.getElementById("predictionLoader");
  if (img) {
    img.style.display = display ? "block" : "none";
  }
}

// return the value of the radio button that is checked
// return an empty string if none are checked, or
// there are no radio buttons
export function getCheckedValue(radioObj) {
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

// Only used in Frontmatter views, currently not an active project and not invoked,
// so not exporting.
function Debug(msg, append) {
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

