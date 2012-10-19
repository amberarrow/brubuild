#include <cstdlib>
#include <iostream>

extern "C" {
#include "planet.h"
}

using namespace std;

// return name of planet defined by argument
int main ( int argc, char **argv ) {
    if ( 1 == argc ) {
        cerr << "Need planet index" << endl;
        exit( 1 );
    }

    int const idx = atoi( argv[ 1 ] );
    cout << "Hello " << planet( idx ) << endl;
}  // main
