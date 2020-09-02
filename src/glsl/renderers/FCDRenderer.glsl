// #package glsl/shaders

// #include ../mixins/unproject.glsl
// #include ../mixins/intersectCube.glsl

// #section FCDConvection/compute

#version 310 es
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform ivec3 uSize;
uniform vec3 uLight;
uniform float uAbsorptionCoefficient;
uniform int uSteps;
uniform float uRatio;
layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityRead;
layout (r32f, binding = 0) writeonly highp uniform image3D uEnergyDensityWrite;
layout (r32f, binding = 1) readonly highp uniform image3D uTotalEnergyDensityRead;
layout (r32f, binding = 1) writeonly highp uniform image3D uTotalEnergyDensityWrite;

uniform mediump sampler3D uVolume;

uniform mediump sampler2D uTransferFunction;

void main() {
    ivec3 position = ivec3(gl_GlobalInvocationID);

    if (position.x < 1 || position.y < 1 || position.z < 1 ||
    position.x >= uSize.x - 1 || position.y >= uSize.y - 1 || position.z >= uSize.z - 1) {
        return;
    }

    float val = texture(uVolume, vec3(position) / vec3(uSize)).r;

    vec4 colorSample = texture(uTransferFunction, vec2(val, 0.5));

    float absorption = colorSample.a * uAbsorptionCoefficient;
    float revAbsorption = float(1) - absorption;

    for (int i = 0; i < uSteps; i++) {
        vec4 center = imageLoad(uEnergyDensityRead, position);
        float radiance = center.r;

        vec3 grad = vec3(
            uLight.x < 0.0 ?
                imageLoad(uEnergyDensityRead, position + ivec3(1,  0, 0)).r - radiance :
                radiance - imageLoad(uEnergyDensityRead, position + ivec3(-1,  0, 0)).r,
            uLight.y < 0.0 ?
                imageLoad(uEnergyDensityRead, position + ivec3(0,  1, 0)).r - radiance :
                radiance - imageLoad(uEnergyDensityRead, position + ivec3(0, -1, 0)).r,
            uLight.z < 0.0 ?
                imageLoad(uEnergyDensityRead, position + ivec3(0,  0, 1)).r - radiance :
                radiance - imageLoad(uEnergyDensityRead, position + ivec3(0,  0, -1)).r
        );
        // (1 - absorption) * (p - 1/2 deltap)
        float convectionDelta = -dot(uLight, grad) * 0.5 / uRatio;

        float new = revAbsorption * (radiance + convectionDelta);

        vec4 final = vec4(new, 0, 0, 0);

        imageStore(uEnergyDensityWrite, position, final);

        vec4 total = imageLoad(uTotalEnergyDensityRead, position);
        imageStore(uTotalEnergyDensityWrite, position, total + final - radiance);
    }
}

// #section FCDConvectionPL/compute

#version 310 es
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform ivec3 uSize;
uniform vec3 uLight;
uniform float uAbsorptionCoefficient;
uniform int uSteps;
uniform float uRatio;
layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityRead;
layout (r32f, binding = 0) writeonly highp uniform image3D uEnergyDensityWrite;
layout (r32f, binding = 1) readonly highp uniform image3D uTotalEnergyDensityRead;
layout (r32f, binding = 1) writeonly highp uniform image3D uTotalEnergyDensityWrite;

uniform mediump sampler3D uVolume;

uniform mediump sampler2D uTransferFunction;

void main() {
    ivec3 position = ivec3(gl_GlobalInvocationID);

    if (position.x < 1 || position.y < 1 || position.z < 1 ||
    position.x >= uSize.x - 1 || position.y >= uSize.y - 1 || position.z >= uSize.z - 1 ||
    distance(vec3(position), uLight) <= 2.0) {
        return;
    }

    vec3 lightDirection = normalize(vec3(position) - uLight);
//    imageStore(uEnergyDensityWrite, position, vec4(lightDirection, 0));
//    return;
    float val = texture(uVolume, vec3(position) / vec3(uSize)).r;

    vec4 colorSample = texture(uTransferFunction, vec2(val, 0.5));

    float absorption = colorSample.a * uAbsorptionCoefficient;
    float revAbsorption = float(1) - absorption;

    for (int i = 0; i < uSteps; i++) {
        vec4 center = imageLoad(uEnergyDensityRead, position);
        float radiance = center.r;

        vec3 grad = vec3(
        lightDirection.x < 0.0 ?
        imageLoad(uEnergyDensityRead, position + ivec3(1,  0, 0)).r - radiance :
        radiance - imageLoad(uEnergyDensityRead, position + ivec3(-1,  0, 0)).r,
        lightDirection.y < 0.0 ?
        imageLoad(uEnergyDensityRead, position + ivec3(0,  1, 0)).r - radiance :
        radiance - imageLoad(uEnergyDensityRead, position + ivec3(0, -1, 0)).r,
        lightDirection.z < 0.0 ?
        imageLoad(uEnergyDensityRead, position + ivec3(0,  0, 1)).r - radiance :
        radiance - imageLoad(uEnergyDensityRead, position + ivec3(0,  0, -1)).r
        );
        // (1 - absorption) * (p - 1/2 deltap)
        float convectionDelta = -dot(lightDirection, grad) * 0.5 / revAbsorption;

        float new = revAbsorption * (radiance + convectionDelta);

        vec4 final = vec4(new, 0, 0, 0);

        imageStore(uEnergyDensityWrite, position, final);

        vec4 total = imageLoad(uTotalEnergyDensityRead, position);
        imageStore(uTotalEnergyDensityWrite, position, total + final - radiance);
    }
}

// #section FCDDiffusion/compute

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

//        float dl    = imageLoad(uEnergyDensityRead, position + ivec3(-1, -1, 0)).r;
//        float ul    = imageLoad(uEnergyDensityRead, position + ivec3(-1,  1,  0)).r;
//        float dr    = imageLoad(uEnergyDensityRead, position + ivec3( 1, -1,  0)).r;
//        float ur    = imageLoad(uEnergyDensityRead, position + ivec3( 1,  1,  0)).r;
//        float left  = imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  0)).r;
//        float right = imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  0)).r;
//        float down  = imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  0)).r;
//        float up    = imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  0)).r;

//        float laplace = 0.25 * dl + 0.25 * ul + 0.25 * dr + 0.25 * ur + 0.5 * left + 0.5 * right + 0.5 * down + 0.5 * up - 3.0 * radiance;

        float left      = imageLoad(uEnergyDensityRead, position + ivec3(-1,  0,  0)).r;
        float right     = imageLoad(uEnergyDensityRead, position + ivec3( 1,  0,  0)).r;
        float down      = imageLoad(uEnergyDensityRead, position + ivec3( 0, -1,  0)).r;
        float up        = imageLoad(uEnergyDensityRead, position + ivec3( 0,  1,  0)).r;
        float back      = imageLoad(uEnergyDensityRead, position + ivec3( 0, 0, -1)).r;
        float forward   = imageLoad(uEnergyDensityRead, position + ivec3( 0,  0, 1)).r;

        left            += imageLoad(uEnergyDensityDiffusionRead, position + ivec3(-1,  0,  0)).r;
        right           += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 1,  0,  0)).r;
        down            += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0, -1,  0)).r;
        up              += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0,  1,  0)).r;
        back            += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0, 0, -1)).r;
        forward         += imageLoad(uEnergyDensityDiffusionRead, position + ivec3( 0,  0, 1)).r;

        float laplace = 0.5 * left + 0.5 * right + 0.5 * down + 0.5 * up + 0.5 * back + 0.5 * forward - 3.0 * radiance;

        float delta = laplace * radiance * scattering / uRatio;
        vec4 final = vec4(delta, 0, 0, 0);

        imageStore(uEnergyDensityDiffusionWrite, position, final);
    }
}

// #section FCDDeleteTexture/compute

#version 310 es
precision highp float;
layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform ivec3 uSize;

layout (r32f, binding = 0) readonly highp uniform image3D uEnergyDensityRead;
layout (r32f, binding = 1) readonly highp uniform image3D uTotalEnergyDensityRead;
layout (r32f, binding = 1) writeonly highp uniform image3D uTotalEnergyDensityWrite;

void main() {
    ivec3 position = ivec3(gl_GlobalInvocationID);
    if (position.x < 1 || position.y < 1 || position.z < 1 ||
    position.x >= uSize.x - 1 || position.y >= uSize.y - 1 || position.z >= uSize.z - 1) {
        return;
    }
    vec4 val = imageLoad(uEnergyDensityRead, position);
    vec4 original = imageLoad(uTotalEnergyDensityRead, position);
    imageStore(uTotalEnergyDensityWrite, position, original - val);
}

// #section FCDGenerate/vertex

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

// #section FCDGenerate/fragment

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
        oColor = vec4(1.0, 1.0, 1.0, 1.0);
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

// #section FCDIntegrate/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;
out vec2 vPosition;

void main() {
    vPosition = (aPosition + 1.0) * 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section FCDIntegrate/fragment

#version 300 es
precision mediump float;

uniform mediump sampler2D uAccumulator;
uniform mediump sampler2D uFrame;

in vec2 vPosition;
out vec4 oColor;

void main() {
    oColor = texture(uFrame, vPosition);
}

// #section FCDRender/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;
out vec2 vPosition;

void main() {
    vPosition = (aPosition + 1.0) * 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section FCDRender/fragment

#version 300 es
precision mediump float;

uniform mediump sampler2D uAccumulator;

in vec2 vPosition;
out vec4 oColor;

void main() {
    oColor = texture(uAccumulator, vPosition);
}

// #section FCDReset/vertex

#version 300 es
precision mediump float;

layout(location = 0) in vec2 aPosition;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
}

// #section FCDReset/fragment

#version 300 es
precision mediump float;

out vec4 oColor;

void main() {
    oColor = vec4(0.0, 0.0, 0.0, 1.0);
}
