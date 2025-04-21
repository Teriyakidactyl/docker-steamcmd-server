script overrides?


create wrappers?

steamcmd update
steamcmd update appid
steamcmd test

wine init
wine test

gameserver start (supervisor, like supervisord, s6, runit, tini)
gameserver stop
gameserver update (steamcmd update appid)
gameserver test
gameserver backup

Auto sourced app scripts?

base image
    up.sh
    logging
    steamcmd
    wine
    boxes

APPs bring their own 'server_start' function? (which can call other custom fuctions)

all supported by logging_functions

When considering Docker's single process principle, the details you would pass to a single process manager (which would then be the container's PID 1) would be tailored to managing that single, primary application process effectively and leveraging Docker's inherent capabilities. Here's how you might alter those details:

1. Simplified Execution Details:

    Command to Execute: This remains the most crucial detail, specifying how to start your main application.
    Working Directory: Still relevant if your application requires a specific working directory.
    Environment Variables: Important for configuring the application within the container.
    User and Group: Setting the user and group for the application process is still a good security practice within the container.

2. Lifecycle Management Focused on Docker:

    Restart Policy (Potentially Less Critical for the Manager Itself): Since Docker has its own --restart policies at the container level, the internal process manager might have a simpler restart policy (e.g., just attempt to restart a few times before giving up and letting Docker handle the container restart). Alternatively, the internal manager might rely entirely on Docker's restart mechanism.
    Stop Signal: The process manager must be configured to handle the SIGTERM signal gracefully, as this is the signal Docker sends to initiate container shutdown. Proper handling involves cleaning up resources and exiting cleanly.
    Kill Signal (Less Relevant for the Manager's Configuration): The process manager doesn't typically need to configure a "kill signal" for itself. If it fails to exit after SIGTERM, Docker will eventually send SIGKILL.
    Stop Timeout (More About the Application): The process manager might need to configure a timeout for its managed application to shut down gracefully after receiving a stop signal, before the manager itself exits (or potentially sends a more forceful signal to the application if it has that capability).

3. Leveraging Docker for Monitoring and Health Checks:

    Health Check Command/Script (Less Emphasis on Internal Manager): Instead of the internal process manager performing its own detailed health checks, you would ideally rely on Docker's built-in HEALTHCHECK instruction in the Dockerfile. This keeps the container's health status visible to Docker and orchestration platforms. The internal manager's monitoring might be simpler – just ensuring the main process is running.
    Exit Codes as Health Indicators: The primary way the internal manager communicates the health of the application to Docker is through its exit code when the container is stopped. A non-zero exit code can signal a failure.

4. Logging Handled by Docker:

    Standard Output (stdout) and Standard Error (stderr) Redirection: The process manager should primarily direct the application's stdout and stderr to the container's stdout and stderr. Docker's logging drivers will then handle the collection and management of these logs. The internal manager doesn't usually need to implement its own complex logging to files.

5. Simpler Process Identification:

    PID 1: If the process manager is the single process manager we're discussing (running as PID 1), it directly manages the execution of the main application. It doesn't need to look for existing PIDs in the same way a standalone process manager might.

Example Scenario:

Imagine a simple container running a web server. The Dockerfile might have:
Dockerfile

FROM ...
WORKDIR /app
COPY your_web_server /app/
EXPOSE 80

HEALTHCHECK --interval=5s --timeout=3s CMD curl -f http://localhost:80/ || exit 1

CMD ["./your_web_server"]

In this case, ./your_web_server is the single process managed directly by Docker (as PID 1). Docker uses the HEALTHCHECK to monitor its health and the CMD to execute it. Docker's restart policy would handle restarts if the server crashes. A separate, more complex process manager within the container isn't necessary.

When a Lightweight Process Manager is Used as PID 1:

If you do use a lightweight process manager like tini or dumb-init as the ENTRYPOINT to handle signal forwarding and zombie reaping, the CMD would then specify how to run your main application. These lightweight init systems don't typically have extensive process management features like restart policies or health checks for the application itself; they primarily ensure clean signal handling for the main process that they spawn. You'd still rely on Docker's restart policies and health checks.

Key Takeaway:

When adhering to Docker's single process principle, the focus of any process management within the container shifts towards ensuring the main application runs correctly, handles signals gracefully for container lifecycle events, and exposes its health in a way that Docker can understand (primarily through exit codes and the HEALTHCHECK). You leverage Docker for the broader container lifecycle management tasks like restarts and logging.