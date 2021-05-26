// __multiversion__
// This signals the loading code to prepend either #version 100 or #version 300 es as apropriate.

#include "fragmentVersionCentroidUV.h"
#include "uniformEntityConstants.h"
#include "uniformPerFrameConstants.h"
#include "uniformShaderConstants.h"
#include "util.h"

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;
LAYOUT_BINDING(1) uniform sampler2D TEXTURE_1;

#ifdef USE_MULTITEXTURE
	LAYOUT_BINDING(2) uniform sampler2D TEXTURE_2;
#endif

varying vec4 light;
varying vec4 fogColor;
varying highp vec3 wpos;
varying highp float dep;

#ifdef COLOR_BASED
	varying vec4 vertColor;
#endif

#ifdef USE_OVERLAY
    // When drawing horses on specific android devices, overlay color ends up being garbage data.
    // Changing overlay color to high precision appears to fix the issue on devices tested
	varying highp vec4 overlayColor;
#endif

#ifdef TINTED_ALPHA_TEST
	varying float alphaTestMultiplier;
#endif

#ifdef GLINT
	varying vec2 layer1UV;
	varying vec2 layer2UV;
	varying vec4 tileLightColor;
	varying vec4 glintColor;
#endif

vec4 glintBlend(vec4 dest, vec4 source) {
	// glBlendFuncSeparate(GL_SRC_COLOR, GL_ONE, GL_ONE, GL_ZERO)
	return vec4(source.rgb * source.rgb, source.a) + vec4(dest.rgb, 0.0);
}

#include "bsbe.cs.glsl"
#ifdef USE_EMISSIVE
#ifdef USE_ONLY_EMISSIVE
#define NEEDS_DISCARD(C) (C.a == 0.0 || C.a == 1.0 )
#else
#define NEEDS_DISCARD(C)	(C.a + C.r + C.g + C.b == 0.0)
#endif
#else
#ifndef USE_COLOR_MASK
#define NEEDS_DISCARD(C)	(C.a < 0.5)
#else
#define NEEDS_DISCARD(C)	(C.a == 0.0)
#endif
#endif

void main()
{
	vec4 color = vec4(1.0);

#ifndef NO_TEXTURE
#if !defined(TEXEL_AA) || !defined(TEXEL_AA_FEATURE)
	color = texture2D( TEXTURE_0, uv );
#else
	color = texture2D_AA(TEXTURE_0, uv);
#endif // !defined(TEXEL_AA) || !defined(TEXEL_AA_FEATURE)

#ifdef MASKED_MULTITEXTURE
	vec4 tex1 = texture2D( TEXTURE_1, uv );

	// If tex1 has a non-black color and no alpha, use color; otherwise use tex1
	float maskedTexture = ceil( dot( tex1.rgb, vec3(1.0, 1.0, 1.0) ) * ( 1.0 - tex1.a ) );
	color = mix(tex1, color, clamp(maskedTexture, 0.0, 1.0));
#endif // MASKED_MULTITEXTURE

#if defined(ALPHA_TEST) && !defined(USE_MULTITEXTURE) && !defined(MULTIPLICATIVE_TINT)
	if(NEEDS_DISCARD(color))
		discard;
#endif // ALPHA_TEST

#ifdef TINTED_ALPHA_TEST
vec4 testColor = color;
testColor.a *= alphaTestMultiplier;
	if(NEEDS_DISCARD(testColor))
		discard;
#endif // TINTED_ALPHA_TEST
#endif // NO_TEXTURE

#ifdef COLOR_BASED
	color *= vertColor;
#endif

#ifdef MULTI_COLOR_TINT
	// Texture is a mask for tinting with two colors
	vec2 colorMask = color.rg;

	// Apply the base color tint
	color.rgb = colorMask.rrr * CHANGE_COLOR.rgb;

	// Apply the secondary color mask and tint so long as its grayscale value is not 0
	color.rgb = mix(color, colorMask.gggg * MULTIPLICATIVE_TINT_CHANGE_COLOR, ceil(colorMask.g)).rgb;
#else

#ifdef USE_COLOR_MASK
	color.rgb = mix(color.rgb, color.rgb*CHANGE_COLOR.rgb, color.a);
	color.a *= CHANGE_COLOR.a;
#endif

#ifdef ITEM_IN_HAND
	color.rgb = mix(color.rgb, color.rgb*CHANGE_COLOR.rgb, vertColor.a);
#if defined(MCPE_PLATFORM_NX) && defined(NO_TEXTURE) && defined(GLINT)
	// TODO(adfairfi): This needs to be properly fixed soon. We have a User Story for it in VSO: 102633
	vec3 dummyColor = texture2D(TEXTURE_0, vec2(0.0, 0.0)).rgb;
	color.rgb += dummyColor * 0.000000001;
#endif
#endif // MULTI_COLOR_TINT

#endif

#ifdef USE_MULTITEXTURE
	vec4 tex1 = texture2D( TEXTURE_1, uv );
	vec4 tex2 = texture2D( TEXTURE_2, uv );
	color.rgb = mix(color.rgb, tex1.rgb, tex1.a);
#ifdef ALPHA_TEST
	if (color.a < 0.5 && tex1.a == 0.0) {
		discard;
	}
#endif

#ifdef COLOR_SECOND_TEXTURE
	if (tex2.a > 0.0) {
		color.rgb = tex2.rgb + (tex2.rgb * CHANGE_COLOR.rgb - tex2.rgb)*tex2.a;//lerp(tex2.rgb, tex2 * changeColor.rgb, tex2.a)
	}
#else
	color.rgb = mix(color.rgb, tex2.rgb, tex2.a);
#endif
#endif

#ifdef MULTIPLICATIVE_TINT
	vec4 tintTex = texture2D(TEXTURE_1, uv);
#ifdef MULTIPLICATIVE_TINT_COLOR
	tintTex.rgb = tintTex.rgb * MULTIPLICATIVE_TINT_CHANGE_COLOR.rgb;
#endif

#ifdef ALPHA_TEST
	color.rgb = mix(color.rgb, tintTex.rgb, tintTex.a);
	if (color.a + tintTex.a <= 0.0) {
		discard;
	}
#endif

#endif

#ifdef USE_OVERLAY
	//use either the diffuse or the OVERLAY_COLOR
	color.rgb = mix(color, overlayColor, overlayColor.a).rgb;
#endif

#ifdef USE_EMISSIVE
	//make glowy stuff
	color *= mix(vec4(1.0), light, color.a );
#else
	color *= light;
#endif
	color.rgb = toLinear(color.rgb);
	highp vec3 uppos = normalize(vec3(0.0,abs(wpos.y),0.0));
	vec3 newfc = rendersky(normalize(wpos),uppos);
	if(dep > 0.1) color.rgb = mix(color.rgb,newfc,saturate(length(wpos)*(0.001+0.003*rain)));

	//apply fog
	if(FOG_CONTROL.x == 0.0) color.rgb = mix( color.rgb, toLinear(fogColor.rgb), pow(fogColor.a, 5.0));

	color.rgb = colorcorrection(color.rgb);

#ifdef GLINT
	// Applies color mask to glint texture instead and blends with original color
	vec4 layer1 = texture2D(TEXTURE_1, fract(layer1UV)).rgbr * glintColor;
	vec4 layer2 = texture2D(TEXTURE_1, fract(layer2UV)).rgbr * glintColor;
	vec4 glint = (layer1 + layer2) * tileLightColor;

	color = glintBlend(color, glint);
#endif

	//WARNING do not refactor this
#ifdef UI_ENTITY
	color.a *= HUD_OPACITY;
#endif
	gl_FragColor = color;
}
