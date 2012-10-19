#include <stdio.h>
#include <stdlib.h>

#include "planet.h"

// return name of planet defined by argument
const char *planet( const int i ) {
    static const char *names[] = {
        "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"
    };

    if ( i < 0 || i > 7 ) {
        fprintf( stderr, "Bad index: %d\n", i );
        exit( 1 );
    }
    return names[ i ];
}  // planet
