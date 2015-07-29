function setCookie(name,value,expiredays)
{
  var exdate = new Date();
  exdate.setDate(exdate.getDate()+expiredays);
  document.cookie = name + "=" + escape(value)+
    ((expiredays==null) ? "" : ";expires="+exdate.toGMTString());
}

var gCharts = {};
function loadChart(id, url)
{
  var req = new XMLHttpRequest();
  req.onreadystatechange = function()
  { 
    if (req.readyState == 4)
    {
      if (req.status == 200)
      {
        var old = gCharts[id];
        if (old) { old.destroy(); }
        var obj = document.getElementById(id);
        var data = JSON.parse(req.responseText);
        data.chart.renderTo = id;
		    gCharts[id] = new Highcharts.Chart(data);
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

function toggleVisibility(id)
{
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

function selMenuItem(id, value)
{
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

sfHover = function()
{
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
if (window.attachEvent)
{
  window.attachEvent("onload", sfHover);
}
