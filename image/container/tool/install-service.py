#!/usr/bin/python3 -u
import os
import subprocess

SERVICE_DIR = "/container/service"
INSTALL_FILENAME = "install.sh"
PROCESS_FILENAME = "process.sh"
MULTIPLE_PROCESS_MARKER = "/container/multiple_process_stack_added"

def run_script(script_path):
    """Run a shell script and remove it afterward."""
    print(f"run {script_path}")
    subprocess.call([script_path], shell=True)
    print(f"remove {script_path}\n")
    os.remove(script_path)

def process_service(service_path):
    """Process the install and process scripts for a given service."""
    install_script = os.path.join(service_path, INSTALL_FILENAME)
    process_script = os.path.join(service_path, PROCESS_FILENAME)
    global nb_process

    if os.path.isfile(install_script):
        run_script(install_script)

    if os.path.isfile(process_script):
        nb_process += 1

def add_multiple_process_stack():
    """Add multiple process stack if not already added."""
    if not os.path.exists(MULTIPLE_PROCESS_MARKER):
        print("This image has multiple process.")
        subprocess.call(["apt-get update"], shell=True)
        subprocess.call(["/container/tool/add-multiple-process-stack"], shell=True)
        print("For better image build process consider adding:")
        print("\"/container/tool/add-multiple-process-stack\" after an apt-get update in your Dockerfile.")

def main():
    global nb_process
    nb_process = 0

    print("install-service")

    # Auto run global install script if available
    global_install_script = os.path.join(SERVICE_DIR, INSTALL_FILENAME)
    if os.path.isfile(global_install_script):
        run_script(global_install_script)

    # Process install script of services in /container/service
    for service in sorted(os.listdir(SERVICE_DIR)):
        service_path = os.path.join(SERVICE_DIR, service)
        if os.path.isdir(service_path):
            process_service(service_path)

    print(f"{nb_process} process found.")

    # Handle multiple processes
    if nb_process > 1:
        add_multiple_process_stack()

if __name__ == "__main__":
    main()
