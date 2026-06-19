
uniform sampler2D g_Texture0; // {"material":"framebuffer","label":"ui_editor_properties_framebuffer","hidden":true}
uniform float g_AudioSpectrum64Left[64];
uniform float R; // {"material":"R","default":0.3,"range":[0,1]}
uniform vec3 u_userNewColor; // {"default":"1 1 1","material":"color","type":"color"}
uniform float u_soundStrength; // {"material":"Sound Strength","default":0.1,"range":[0.01,0.5]}

uniform float g_AudioSpectrum64Right[64];




const float BAR_NUM = 64.;
const float PI = 3.1415926;
const float RECT_WIDTH = 0.004;

//make UV from -0.5 to 0.5
vec2 centerUV(vec2 uv)
{
    uv = uv - 0.5;
    return uv;
}

vec2 rotate(vec2 uv, float th)
{
    return mul( uv ,mat2(cos(th),sin(th),-sin(th),cos(th)));
}

float unionSD(float a, float b)
{
    return min(a, b);
}

float sdCircle(vec2 uv, float r, vec2 offset)
{
    uv = centerUV(uv);
    float x = uv.x - offset.x;
    float y = uv.y - offset.y;
    
    return length(vec2(x,y)) - r;
}

float sdRect(vec2 uv, float width, float height, float angle, vec2 offset)
{
    uv = centerUV(uv);
    float x = uv.x - offset.x;
    float y = uv.y - offset.y;
    vec2 rotated = rotate(vec2(x,y), angle);
    
    x = rotated.x;
    y = rotated.y;
    
    return  max(abs(x) - width, abs(y) - height);
}

float volumNum(float barID)
{
    // GLSL: g_AudioSpectrum64Left is float[64], not vec4[]. Use scalar index.
    int idx = int(barID);
    idx = clamp(idx, 0, 63);
    return clamp(0. , 1., g_AudioSpectrum64Left[idx]);
}

vec3 drawSence(vec2 uv)
{
    vec4 col = vec4(0.,0.,0.,0.);
    
    for(float i = 0.; i < BAR_NUM; ++i)
    {
        float theta = PI * i *2./BAR_NUM ;
        float height = volumNum(i) * u_soundStrength;
        float rect = sdRect(uv, RECT_WIDTH, height, theta, vec2(R*sin(theta), R*cos(theta)));

        float circle1 = sdCircle(uv, RECT_WIDTH, vec2((R - height)*sin(theta), (R - height)*cos(theta)));
        float circle2 = sdCircle(uv, RECT_WIDTH, vec2((R + height)*sin(theta), (R + height)*cos(theta)));

        float sence = unionSD(rect, circle1);
        sence = unionSD(sence, circle2);

        col = vec4(mix(u_userNewColor, col, step(0., sence)), 1.);
    }
    
    return col;
}

varying vec2 v_TexCoord;

void main() {
	vec2 uv = v_TexCoord.xy;
	vec3 col = drawSence(uv);

	gl_FragColor = vec4(col, 1.);
}
