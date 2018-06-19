#
# RDIST Application Distribution File
#
# PURPOSE: deploy application from test.babel.hathitrust.org to production
#
# Destination Servers
#
NASMACC = ( nas-macc.umdl.umich.edu )
NASICTC = ( nas-ictc.umdl.umich.edu )

#
# File Directories to be released (source) and (destination)
#
APP_src  = ( /htapps/test.babel/crms )
APP_dest = ( /htapps/babel/crms )

#
# Release instructions
# -oremove omitted so we don't clobber pw.cfg files and prep directory
#
( ${APP_src} ) -> ( ${NASMACC} ${NASICTC} )
        install ${APP_dest};
        except_pat ( \\.git );
        #notify hathitrust-release@umich.edu ;
