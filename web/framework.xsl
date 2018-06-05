<?xml version="1.0" encoding="UTF-8" ?>

<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:METS="http://www.loc.gov/METS/"
  xmlns:PREMIS="http://www.loc.gov/standards/premis"
  >

  <xsl:import href="../../m/mdp/MBooks/framework.xsl"/>

  <!-- Navigation bar -->
  <xsl:template name="subnav_header">

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

