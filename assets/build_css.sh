# FIXME: probably don't need the $* parameter?
# Can I take all of these and squish them all into a single main.css file?
sass $* assets/styles:public/styles --style=compressed --load-path=node_modules
sass $* node_modules/tippy.js/dist/tippy.css public/styles/tippy.css
