// #package glsl/shaders

// #include ../mixins/unproject.glsl
// #include ../mixins/intersectCube.glsl

// #section RCDMonteCarlo/compute

#version 310 es
#define DIRECTIONAL 0.5
#define POINT 1.5
#define FLT_MAX 3.402823466e+38
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

@PhotonRCD

layout (std430, binding = 0) buffer bPhotons {
    PhotonRCD sPhotons[];
};

layout (std430, binding = 1) readonly buffer bLights {
    vec4 lights[];
};

uniform ivec3 uSize;
uniform float uAbsorptionCoefficient;
uniform float uMajorant;
uniform float uRandSeed;
uniform uint uSteps;
layout (r32f, binding = 0) writeonly highp uniform image3D uEnergyDensityWrite;

uniform mediump sampler3D uVolume;

uniform mediump sampler2D uTransferFunction;

@rand

vec4 getRandomLight(vec2 randState) {
    float divider = 1.0 / float(lights.length());
    randState = rand(randState);
    return lights[int(randState.x / divider)];
}

void resetPhoton(vec2 randState, inout PhotonRCD photon) {
    vec3 from = vec3(gl_GlobalInvocationID) / vec3(uSize);
    vec4 to = getRandomLight(randState);
//    photon.direction = normalize(to.xyz - from);
    if (to.a < DIRECTIONAL) {
        photon.direction = -normalize(to.xyz);
        photon.distance = FLT_MAX;
    } else {
        photon.direction = normalize(to.xyz - from);
        photon.distance = distance(from, to.xyz);
    }
    photon.position = from;
    photon.transmittance = 1.0;
    photon.travelled = 0.0;

}

vec4 sampleVolumeColor(vec3 position) {
    vec2 volumeSample = texture(uVolume, position).rg;
//    vec4 transferSample = texture(uTransferFunction, volumeSample);
    vec4 transferSample = texture(uTransferFunction, vec2(volumeSample.r, 0.5));
    return transferSample;
}

void main() {
    uvec3 globalSize = gl_WorkGroupSize * gl_NumWorkGroups;
    uint globalInvocationIndex =
        gl_GlobalInvocationID.z * globalSize.x * globalSize.y +
        gl_GlobalInvocationID.y * globalSize.x +
        gl_GlobalInvocationID.x;
    PhotonRCD photon = sPhotons[globalInvocationIndex];

    vec2 r = rand((vec2(gl_GlobalInvocationID.xy) + vec2(gl_GlobalInvocationID.yz)) * uRandSeed);
//    float d = distance(photon.position, light / vec3(uSize));
//    imageStore(uEnergyDensityWrite, ivec3(gl_GlobalInvocationID), vec4(d));
//    imageStore(uEnergyDensityWrite, ivec3(gl_GlobalInvocationID), vec4(photon.transmittance, 0));
    for (uint i = 0u; i < uSteps; i++) {
        r = rand(r);
        float t = -log(r.x) / uMajorant;
        vec3 newPosition = photon.position + t * photon.direction;
        float distance = distance(photon.position, newPosition);
        photon.position = newPosition;
        photon.travelled += distance;

        vec4 volumeSample = sampleVolumeColor(photon.position);

        float muAbsorption = volumeSample.a * uAbsorptionCoefficient;

        float muNull = uMajorant - muAbsorption;
        float muMajorant = muAbsorption + abs(muNull);
        float PNull = abs(muNull) / muMajorant;
        float PAbsorption = muAbsorption / muMajorant;

        if (photon.travelled >= photon.distance ||
            any(greaterThan(photon.position, vec3(1))) || any(lessThan(photon.position, vec3(0)))) {
            // out of bounds
            float radiance = photon.transmittance;
            photon.samples++;
            photon.radiance += (radiance - photon.radiance) / float(photon.samples);
            imageStore(uEnergyDensityWrite, ivec3(gl_GlobalInvocationID), vec4(photon.radiance));
            resetPhoton(r, photon);
        } else if (r.y < PAbsorption) {
            // absorption
            float weightA = muAbsorption / (uMajorant * PAbsorption);
            photon.transmittance *= 1.0 - weightA;
        } else {
            // null collision
            float weightN = muNull / (uMajorant * PNull);
            photon.transmittance *= weightN;
        }
    }

    sPhotons[globalInvocationIndex] = photon;
}

// #section RCDResetPhotons/compute

#version 310 es
#define DIRECTIONAL 0.5
#define POINT 1.5
#define FLT_MAX 3.402823466e+38
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform float uRandSeed;
uniform ivec3 uSize;

@rand

@PhotonRCD

layout (std430, binding = 0) buffer bPhotons {
    PhotonRCD sPhotons[];
};

layout (std430, binding = 1) readonly buffer bLights {
    vec4 lights[];
};

vec4 getRandomLight(vec2 randState) {
    float divider = 1.0 / float(lights.length());
    randState = rand(randState);
    return lights[int(randState.x / divider)];
}
void main() {
    PhotonRCD photon;
    vec2 randState = rand(vec2(gl_GlobalInvocationID) * uRandSeed);
    vec3 from = vec3(gl_GlobalInvocationID) / vec3(uSize);
    vec4 to = getRandomLight(randState);
//    photon.direction = normalize(to.xyz - from);
    if (to.a < DIRECTIONAL) {
        photon.direction = -normalize(to.xyz);
        photon.distance = FLT_MAX;
    } else {
        photon.direction = normalize(to.xyz - from);
        photon.distance = distance(from, to.xyz);
    }
    photon.position = from;
    photon.transmittance = 1.0;
    photon.travelled = 0.0;
    photon.radiance = 0.05;
    photon.samples = 0u;
    uvec3 globalSize = gl_WorkGroupSize * gl_NumWorkGroups;
    uint globalInvocationIndex =
    gl_GlobalInvocationID.z * globalSize.x * globalSize.y +
    gl_GlobalInvocationID.y * globalSize.x +
    gl_GlobalInvocationID.x;
    sPhotons[globalInvocationIndex] = photon;
}


// #section RCDRayCasting/compute

#version 310 es
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform ivec3 uSize;
uniform float uAbsorptionCoefficient;
uniform float uStepSize;
uniform vec3 uLight;
uniform float uAlphaCorrection;
layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityRead;
layout (r32f, binding = 0) writeonly highp uniform image3D uEnergyDensityWrite;

uniform mediump sampler3D uVolume;
uniform mediump sampler2D uTransferFunction;

vec4 sampleVolumeColor(vec3 position) {
    float volumeSample = texture(uVolume, position).r;
    vec4 transferSample = texture(uTransferFunction, vec2(volumeSample, 0.5));
    return transferSample;
}

void main() {
    ivec3 index = ivec3(gl_GlobalInvocationID);
    vec3 position = vec3(gl_GlobalInvocationID) / vec3(uSize);
    float previousRadiance = imageLoad(uEnergyDensityRead, index).r;
    float rayStepLength = distance(position, uLight) * uStepSize;

    float t = 0.0;
    vec3 pos;
    float absorption;
    float accumulator = 1.0;

    while (t < 1.0 && accumulator > 0.0) {
        pos = mix(position, uLight, t);
        absorption = sampleVolumeColor(pos).a * rayStepLength * uAbsorptionCoefficient * uAlphaCorrection;

        accumulator -= absorption;
        t += uStepSize;
    }

    if (accumulator < 0.0) {
        accumulator = 0.0;
    }

    imageStore(uEnergyDensityWrite, index, vec4(previousRadiance + accumulator));
}

// #section RCDDiffusion/compute

#version 310 es
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform ivec3 uSize;
uniform float scattering;
uniform float uRatio;
layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityRead;
layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityDiffusionRead;
layout (r32f, binding = 1) writeonly highp uniform image3D uEnergyDensityDiffusionWrite;

void main() {
    ivec3 position = ivec3(gl_GlobalInvocationID);

    if (position.x < 1 || position.y < 1 || position.z < 1 ||
    position.x >= uSize.x - 1 || position.y >= uSize.y - 1 || position.z >= uSize.z - 1) {
        return;
    }

    for (int i = 0; i < 1; i++) {
        float radiance = imageLoad(uEnergyDensityRead, position).r;
        radiance += imageLoad(uEnergyDensityDiffusionRead, position).r;

        float left      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  0)).r;
        float leftUp      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  0)).r;
        float leftDown      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  0)).r;
        float right     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  0)).r;
        float rightUp     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  0)).r;
        float rightDown     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  0)).r;
        float down      = imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  0)).r;
        float up        = imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  0)).r;

        float back          = imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0, 0, -1)).r;
        float backLeft      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  -1)).r;
        float backLeftUp      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  -1)).r;
        float backLeftDown      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  -1)).r;
        float backRight     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  -1)).r;
        float backRightUp     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  -1)).r;
        float backRightDown     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  -1)).r;
        float backDown      = imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  -1)).r;
        float backUp        = imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  -1)).r;

        float forward   = imageLoad(uEnergyDensityRead, position + ivec3( 0,  0, 1)).r;
        float forwardLeft      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  1)).r;
        float forwardLeftUp      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  1)).r;
        float forwardLeftDown      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  1)).r;
        float forwardRight     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  1)).r;
        float forwardRightUp     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  1)).r;
        float forwardRightDown     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  1)).r;
        float forwardDown      = imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  1)).r;
        float forwardUp        = imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  1)).r;

        left      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  0)).r;
        leftUp      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  0)).r;
        leftDown      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  0)).r;
        right     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  0)).r;
        rightUp     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  0)).r;
        rightDown     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  0)).r;
        down      += imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  0)).r;
        up        += imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  0)).r;

        back          += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0, 0, -1)).r;
        backLeft      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  -1)).r;
        backLeftUp      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  -1)).r;
        backLeftDown      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  -1)).r;
        backRight     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  -1)).r;
        backRightUp     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  -1)).r;
        backRightDown     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  -1)).r;
        backDown      += imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  -1)).r;
        backUp        += imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  -1)).r;

        forward   += imageLoad(uEnergyDensityRead, position + ivec3( 0,  0, 1)).r;
        forwardLeft      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  1)).r;
        forwardLeftUp      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  1)).r;
        forwardLeftDown      += imageLoad(uEnergyDensityRead, position + ivec3(-1,  -1,  1)).r;
        forwardRight     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  1)).r;
        forwardRightUp     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  1)).r;
        forwardRightDown     += imageLoad(uEnergyDensityRead, position + ivec3( 1,  -1,  1)).r;
        forwardDown      += imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  1)).r;
        forwardUp        += imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  1)).r;

        float laplace = 1.0/48.0 * (backLeftUp + backLeftDown + backRightUp + backRightDown +
        forwardLeftUp + forwardLeftDown + forwardRightUp + forwardRightDown) +
        1.0/8.0 * (backLeft + backRight + backDown + backUp + forwardLeft + forwardRight + forwardDown + forwardUp +
        leftUp + leftDown + rightUp + rightDown) +
        5.0/12.0 * (back + forward + left + right + down + up) -
        25.0/6.0 * radiance;

        float delta = laplace * radiance * scattering / uRatio;
        vec4 final = vec4(delta, 0, 0, 0);

        imageStore(uEnergyDensityDiffusionWrite, position, final);
    }
}

// #section RCDGenerate/vertex

#version 310 es
precision mediump float;

uniform mat4 uMvpInverseMatrix;

layout(location = 0) in vec2 aPosition;
out vec3 vRayFrom;
out vec3 vRayTo;

//debug
out vec2 vPosition;

@unproject

void main() {
    unproject(aPosition, uMvpInverseMatrix, vRayFrom, vRayTo);
    gl_Position = vec4(aPosition, 0.0, 1.0);
    //debug
    vPosition = aPosition * 0.5 + 0.5;
}

// #section RCDGenerate/fragment

#version 310 es
precision mediump float;

//layout (r32f, binding = 2) readonly highp uniform image3D uEnergyDensity;

uniform mediump sampler3D uVolume;
uniform mediump sampler2D uTransferFunction;
uniform mediump sampler3D uEnergyDensity;
uniform mediump sampler3D uEnergyDensityDiffusion;
uniform float uStepSize;
uniform float uOffset;
uniform float uAlphaCorrection;

in vec3 vRayFrom;
in vec3 vRayTo;
out vec4 oColor;

//debug
in vec2 vPosition;


@intersectCube

void main() {
//    float radiance = texture(uEnergyDensity, vec3(vPosition, 90)).r;
//    oColor = vec4(vec3(radiance), 1);
//    return;

    vec3 rayDirection = vRayTo - vRayFrom;
    vec2 tbounds = max(intersectCube(vRayFrom, rayDirection), 0.0);
    if (tbounds.x >= tbounds.y) {
        oColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec3 from = mix(vRayFrom, vRayTo, tbounds.x);
        vec3 to = mix(vRayFrom, vRayTo, tbounds.y);
        float rayStepLength = distance(from, to) * uStepSize;

        float t = 0.0;
        vec3 pos;
        float val;
        vec4 colorSample;
        vec4 accumulator = vec4(0.0);

        float energyDensity;

        while (t < 1.0 && accumulator.a < 0.99) {
            pos = mix(from, to, t);
            val = texture(uVolume, pos).r;

            energyDensity = texture(uEnergyDensity, pos).r;
            energyDensity += texture(uEnergyDensityDiffusion, pos).r;

            colorSample = texture(uTransferFunction, vec2(val, 0.5));
            colorSample.a *= rayStepLength * uAlphaCorrection;
            // utezi z energy density
            colorSample.rgb *= colorSample.a * energyDensity;
            //            colorSample.rgb *= colorSample.a;
//            colorSample.rgb = vec3(energyDensity);
            accumulator += (1.0 - accumulator.a) * colorSample;
            t += uStepSize;
        }

        if (accumulator.a > 1.0) {
            accumulator.rgb /= accumulator.a;
        }

//        oColor = vec4(accumulator.rgb, 1.0);
        oColor = mix(vec4(1), vec4(accumulator.rgb, 1), accumulator.a);
    }
}

// #section RCDIntegrate/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;
out vec2 vPosition;

void main() {
    vPosition = (aPosition + 1.0) * 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section RCDIntegrate/fragment

#version 300 es
precision mediump float;

uniform mediump sampler2D uAccumulator;
uniform mediump sampler2D uFrame;

in vec2 vPosition;
out vec4 oColor;

void main() {
    oColor = texture(uFrame, vPosition);
}

// #section RCDRender/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;
out vec2 vPosition;

void main() {
    vPosition = (aPosition + 1.0) * 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section RCDRender/fragment

#version 300 es
precision mediump float;

uniform mediump sampler2D uAccumulator;

in vec2 vPosition;
out vec4 oColor;

void main() {
    oColor = texture(uAccumulator, vPosition);
}

// #section RCDReset/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section RCDReset/fragment

#version 300 es
precision mediump float;

out vec4 oColor;

void main() {
    oColor = vec4(0.0, 0.0, 0.0, 1.0);
}