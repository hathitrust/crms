function setCookie(name,value,expiredays)
{
  var exdate = new Date();
  exdate.setDate(exdate.getDate()+expiredays);
  document.cookie = name + "=" + escape(value)+
    ((expiredays==null) ? "" : ";expires="+exdate.toGMTString());
}
