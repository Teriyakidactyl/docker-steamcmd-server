# TODO: Implement Proton Branch

## Dockerfile Changes

- [ ] Create a new Dockerfile variant for Proton (e.g., `Dockerfile.proton`)
- [ ] Add build argument to determine Wine/Proton variant (`ARG VARIANT=wine`)
- [ ] Implement conditional installation of Wine or Proton based on `VARIANT`
- [ ] Update base image selection if necessary for Proton support
- [ ] Adjust environment variable settings for Proton (e.g., `PROTON_PATH`, `PROTON_VERSION`)
- [ ] Modify final stage to include Proton-specific configurations

## Script Updates

### update_functions

- [ ] Add Proton-specific update function (e.g., `proton_update()`)
- [ ] Modify `server_update()` to handle Proton installations
- [ ] Update `wine_setup()` to include Proton configuration

### up.sh

- [ ] Add conditional logic to use Proton instead of Wine when specified
- [ ] Update `APP_COMMAND` construction to use Proton when appropriate
- [ ] Modify environment variable setup for Proton (e.g., `PROTON_PATH`, `STEAM_COMPAT_CLIENT_INSTALL_PATH`)

## docker-build.yml Changes

- [ ] Implement matrix strategy to build both Wine and Proton variants:
  ```yaml
  strategy:
    matrix:
      variant: [wine, proton]
  ```
- [ ] Update `docker/metadata-action` step to generate Proton-specific tags:
  ```yaml
  tags: |
    type=raw,value=${{ matrix.variant }}-latest
    type=ref,event=branch,prefix=${{ matrix.variant }}-
    type=semver,pattern={{version}},prefix=${{ matrix.variant }}-
    type=sha,format=long,prefix=${{ matrix.variant }}-
    type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' && matrix.variant == 'wine' }}
  ```
- [ ] Modify `docker/build-push-action` step to use the correct Dockerfile and build args:
  ```yaml
  file: ./Dockerfile.${{ matrix.variant }}
  build-args: |
    VARIANT=${{ matrix.variant }}
  ```

## README.md Updates

- [ ] Add section explaining Proton support and usage
- [ ] Update environment variables and build arguments sections to include Proton-specific options
- [ ] Provide examples of how to use the Proton variant of the image

## Testing

- [ ] Test building both Wine and Proton variants locally
- [ ] Verify multi-arch support for both variants (amd64 and arm64)
- [ ] Test running a game server using the Proton variant
- [ ] Ensure all scripts and functions work correctly with Proton

## Documentation

- [ ] Update any relevant documentation to reflect the addition of Proton support
- [ ] Create or update examples demonstrating how to use the Proton variant in derived images

