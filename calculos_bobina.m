% Definir la constante k
k = 0.68416907*pi;

% Crear una malla de valores para x y z
x = linspace(0, 0.13, 100);  % Rango de x de -2 a 2
z = linspace(0.01, .5, 100); % Rango de z evitando cero
[X, Z] = meshgrid(x, z);

% Calcular y usando la ecuación despejada
% y = k / ( z .* .* (X .^2) (Z.^2 + X.^2).^(-5/2) )
Y = (k.*(Z.^2 + X.^2).^(5/2)) ./ ( Z .* (X .^2) );

% Graficar la superficie
figure;
surf(X, Y, Z, 'EdgeColor', 'none');
xlabel('x');
ylabel('y');
zlabel('z');
title('Gráfica de I=(k*(x^2+a^2)^(5/2))(a^2*x)');
colorbar;

% Ajustar el rango de y para mejor visualización
ylim([0, 600]); % Limitar el eje y a valores entre 0 y 5
xlim([0 0.13]);