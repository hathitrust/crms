sfHover = function() {
	var sfEls = document.getElementById("menu").getElementsByTagName("LI");
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
if (window.attachEvent) window.attachEvent("onload", sfHover);
