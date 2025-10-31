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
      var pdusren = document.getElementById('PDUSREN');
      // TODO: this is a really clunky way of making the mapping from rights name ->
      // rights id (and ultimately the radio button with that id value) available to JavaScript.
      // Ideally, review.tt should query Entitlements.pm and construct JSON with name -> id map
      // as a global variable.
      var icrenButton, pdusrenButton;
      if (icren)
      {
        icrenButton = document.getElementById("r" + icren.title);
      }
      if (pdusren)
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

async function predictRights(id, year, actualPubDate, pub, crown) {
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

function deselectCurrentRights() {
  var rights = document.getElementsByName("rights");
  var sel = GetCheckedValue(rights);
  if (sel) {
    document.getElementById("r" + sel).checked = false;
  }
}

// ajaxURL("predictRights") => "https://babel.hathitrust.org/crms/cgi/predictRights"
function ajaxURL(target) {
  return window.location.protocol + "//" + window.location.host + "/crms/cgi/" + target;
}

function togglePredictionLoader(display) {
  var img = document.getElementById("predictionLoader");
  if (img) {
    img.style.display = display ? "inline-block" : "none";
  }
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
