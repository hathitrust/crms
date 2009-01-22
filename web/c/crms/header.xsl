<?xml version="1.0" encoding="utf-8"?>

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0">

  <xsl:import href="../../m/mdp/MBooks/header.xsl"/>
  
  <xsl:output
    method="xml"
    indent="yes"
    encoding="utf-8"
    doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"
    doctype-public="-//W3C//DTD XHTML 1.0 Strict//EN"
    />

  <xsl:template name="header">
    <div style="background-color:#FFFFFF;border-top:5px solid #494949; height:20px; width:100%;">
      <xsl:call-template name="subnavheaderWrapper"/>
    </div>
  </xsl:template>

 <xsl:template name="subnavheaderWrapper">
   <div id="SubNavHeader">
     <div id="SubNavHeaderCont">
       <xsl:call-template name="subnav_header_short"/>
     </div>
   </div>
 </xsl:template>


  <!-- Navigation bar -->
  <xsl:template name="subnav_header_short">

    <div id="mdpItemBar">
      <div id="ItemBarContainer">

        <!-- Title, Author (short) -->
        <xsl:call-template name="ItemMetadata"/>

        <!-- New Bookmark
        <xsl:call-template name="ItemBookmark"/>
        -->
        <!-- Search 
        <div id="mdpSearch">
          <xsl:call-template name="BuildSearchForm">
            <xsl:with-param name="pSearchForm" select="MdpApp/SearchForm"/>
          </xsl:call-template>
        </div>
        -->
      </div>
    </div>

  </xsl:template>


</xsl:stylesheet>
  
