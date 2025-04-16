        # WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/" && \
        # WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \
        # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files)
        # WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \    

                # NOTE Skipping wine32 i386
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}" && \
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" && \

        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" / && \
        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" / && \