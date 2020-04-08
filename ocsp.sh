#!/bin/bash

COMMAND=$0

print_help() {
    echo "Usage: $COMMAND command [other_command...]"
    echo "Commands:"
    echo "* build                         builds the docker image, name it 'ocsp'"
    echo "* create                        creates the docker container, name it 'ocsp'"
    echo "* start                         starts the 'ocsp' docker container"
    echo "* stop                          stops the 'ocsp' docker container"
    echo "* rm                            removes the 'ocsp' docker container"
    echo "* sign <file.csr> <file.crt>    signs the given csr file and creates the given crt file"
    echo "* rootca <root.crt>             exports the root certificate into the given crt file"
    echo "* revoke <file.crt>             revokes the given crt file"
    echo "* check <root.crt> <file.crt>   checks the OCSP status of the given crt file with the given root certificate"
    echo "* help                          prints this message"
}

if [ "$1" == "" ]; then
    echo "Missing command"
    print_help
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        build)
            echo "Building docker image"
            docker build --tag ocsp docker/
            shift 1
            ;;
        create)
            echo "Creating docker container"
            docker create --tty --interactive --name ocsp --publish 9000:9000 --env "SERVER_NAME=$(hostname)" ocsp
            shift 1
            ;;
        start)
            echo "Starting docker image"
            docker start ocsp
            shift 1
            ;;
        stop)
            echo "Stoping docker image"
            docker stop ocsp
            shift 1
            ;;
        rm)
            echo "Removing docker image"
            docker rm ocsp
            shift 1
            ;;
        sign)
            if [ "$2" == "" ] || [ "$3" == "" ]; then
                echo "Missing arguments for $0 command: <file.csr> <file.crt>"
                print_help
                exit 1
            fi
            echo "Signing certficiate request $2 to $3"
            docker exec --interactive ocsp /sign.sh < "$2" > "$3"
            shift 3
            ;;
        rootca)
            if [ "$2" == "" ]; then
                echo "Missing arguments for $0 command: <root.crt>"
                print_help
                exit 1
            fi
            echo "Exporting root certificate to $2"
            docker exec --interactive ocsp /rootca.sh > "$2"
            shift 2
            ;;
        revoke)
            if [ "$2" == "" ]; then
                echo "Missing arguments for $0 command: <file.crt>"
                print_help
                exit 1
            fi
            echo "Revoking cetificate $2"
            docker exec --interactive ocsp /revoke.sh < "$2"
            shift 2
            ;;
        check)
            if [ "$2" == "" ] || [ "$3" == "" ]; then
                echo "Missing arguments for $0 command: <root.crt> <file.crt>"
                print_help
                exit 1
            fi
            echo "Checking certificate $3 from issuer $2"
            openssl ocsp -issuer "$2" -cert "$3" -CAfile "$2" -url "http://$(hostname):9000" -resp_text
            shift 3
            ;;
        help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown '$1' command"
            print_help
            exit 1
            ;;
    esac

    # Wait a bit before processing the next command
    sleep 1
done
